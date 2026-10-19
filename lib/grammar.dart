import 'package:kerf/ast.dart';
import 'package:petitparser/petitparser.dart';

extension KerfParserExtra<R> on Parser<R> {
  Parser<R> tokenSep() => skip(after: whitespace().plus());
  Parser<String> tokenString(String str) => string(str).skip(after: whitespace().plus());

  Parser<T> assignTo<T>(T value) => map((_)=>value);
}

extension KerfParserExtraTwo<R extends AST> on Parser<R> {
  Parser<R> tokenAST() => token().map((v){
    v.value.start = v.start;
    v.value.stop = v.stop;
    return v.value;
  });
}

class KerfGrammarDefinition extends GrammarDefinition {
  /* ====== Utils Start ====== */
  final Parser _escape = char('\\') & any();
  Parser _string(String wrapChar, String a) => string(wrapChar) & (_escape | noneOf(wrapChar+a).star()) & string(wrapChar);
  Parser __slString(String wrapChar) => _string(wrapChar,"\n\r");
  Parser __mlString(String wrapChar) => _string(wrapChar*3, "");
  
  final Parser _int = digit().plus().flatten().trim();
  final Parser _float = (digit().star() & char(".") & digit().plus()).flatten().trim();


  Block asBlock(AST instruction) => instruction is Block ? instruction : Block([instruction]);

  /* ====== Utils End ====== */
  late final Parser primitiveRule_ = [
    for (final p in ["str", "int", "bool", "float"]) string(p)
  ].toChoiceParser();
  Parser primitiveRule() => primitiveRule_ | string("list");

  /* ====== Expressions Start ====== */
  Parser<NumLiteral> number() => [
    _float.trim().map((e)=>FloatLiteral(double.parse(e))),
    _int.trim().map((e)=>IntLiteral(int.parse(e)))
  ].toChoiceParser().tokenAST();
  Parser _slString() => (__slString("'") | __slString('"')).flatten().trim();
  Parser _mlString() => (__mlString("'") | __mlString('"')).flatten().trim();
  Parser<StringLiteral> strings() => (_mlString() | _slString()).map((e)=>StringLiteral(e)).tokenAST(); 
  Parser<BoolLiteral> boolean() => (string("true") | string("false")).trim().map((e)=>BoolLiteral(e=="true")).tokenAST();
  Parser<ListLiteral> list() => seq2( 
    primitiveRule_.skip(before: char("<"), after: char(">")).optional().skip(after: char("[")),
    (ref0(atom).starSeparated(char(",").trim())).skip(after: char("]"))
  ).trim().map2((optionalType, e)=>ListLiteral(e.elements.cast(), optionalType)).tokenAST();
  Parser<Expression> atom() => (ref0(strings) | ref0(boolean) | ref0(number) | ref0(list) | ref0(expression)).cast<Expression>();
  Parser<Expression> primary() => (
    // grouping
    ref0(expression).skip(before: char("("), after: char(")")) |

    ref0(atom) |
    // sequence accessor
    seq2(ref0(expression), ref0(expression).skip(before:char("["),after:char("]"))).map2((v,key)=>IndexAccess(v,key)) |
    // function calla
    seq2(validIdentifier, ref0(arguments).skip(before: char("("), after: char(")")))
      .map2((name, args) => FunctionCall(name, args))
  ).cast();

  Parser<Expression> expression() {
    final builder = ExpressionBuilder<Expression>();
    
    builder.primitive(ref0(primary));
    
    builder.group().right(
      char('^').trim(), (left, operator, right) => Power(left, right));

    builder.group()
      ..prefix(char("+"), (_,atom)=>Factor(.positive, atom))
      ..prefix(char("-"), (_,atom)=>Factor(.negative, atom));

    builder.group()
      ..left(char('*').trim(), (left, operator, right) => BinaryExpr(left, .multiply, right))
      ..left(char('/').trim(), (left, operator, right) => BinaryExpr(left, .divide, right))
      ..left(char('%').trim(), (left, operator, right) => BinaryExpr(left, .modulo, right));
    builder.group()
      ..left(char('+').trim(), (left, operator, right) => BinaryExpr(left, .plus, right))
      ..left(char('-').trim(), (left, operator, right) => BinaryExpr(left, .minus, right));

    builder.group().prefix(char("!"), (_, a)=>Inversion(a));
    builder.group().left(string("&&"), (l, _, r)=>Conjunction(l,r));
    builder.group().left(string("||"), (l, _, r)=>Disjunction(l,r));

    return [
      // Arithmetic Expressions
      builder.build(),
      // Specials
      /* Motion */
      seq2(
        string("sprite"),
        [
          char("X").assignTo(SPEProperty.x),
          char("Y").assignTo(SPEProperty.y),
          char("Rotation").assignTo(SPEProperty.rotation)
        ].toChoiceParser()
      ).map2((_, prop)=>SpritePositionExpr(prop)),
      /* Sensing */
      seq2(
        string("touching").tokenSep(),
        [
          string("mouse").assignTo((TouchTarget.mouse, null)),
          string("edge").assignTo((TouchTarget.edge, null)),
          seq2(string("sprite").tokenSep(), validIdentifier).map2((_, spriteId)=>(TouchTarget.sprite, spriteId))
        ].toChoiceParser().cast<(TouchTarget, String?)>()
      ).map2((_, target)=>TouchingExpr(target.$1, target.$2))
    ].toChoiceParser().cast<Expression>();
  }
  /* ====== Expressions End ====== */

  
  /* ====== Instructions Start ====== */
  /*    ==== Assignment Start ====    */
  final Parser<String> validIdentifier = (pattern("a-zA-Z_") & pattern("a-zA-Z0-9_").star()).trim().flatten();
  Parser<Identifier> identifier() => validIdentifier.map((s)=>Identifier(s));
  Parser<R> terminator<R>(Parser<R> parser) => parser.skip(after: char(";")).trim();

  Parser<(String, Expression)> namedArgument() => seq2(validIdentifier.skip(after: char("=").trim()), ref0(expression));
  Parser<Argument> argument() => (
    ref0(expression).map((v)=>Argument(v)) | 
    ref0(namedArgument).map((t)=>Argument(t.$2, name: t.$1))
  ).cast();
  Parser<List<Argument>> arguments() => ref0(argument).starSeparated(char(",")).map((e)=>e.elements.cast<Argument>());

  Parser<Assignment> assignment() 
  => terminator(ref0(namedArgument))
    .map((t)=>Assignment(t.$1, t.$2));

  Parser<Declaration> declaration()
  => seq2(
    (string("let")|string("const")).tokenSep(),
    assignment()
  ).map2((d, t)=>Declaration(t.name, t.value));
  /*     ==== Assignment End ====     */

  /* ==== Top-Level Instructions Start ==== */
  /*        === Function Start ===          */
  Parser<List<ArgumentDef>> functionArgDef() 
  => seq2(
    validIdentifier.skip(after: char(":").trim()),
    primitiveRule()
  ).map2((name, type)=>ArgumentDef(name, type)).cast<ArgumentDef>().starSeparated(char(",")).map((e)=>e.elements.cast<ArgumentDef>());

  Parser functionReturnType() => primitiveRule() & string("void");
  Parser<FunctionDef> function() 
  => seq4(
    functionReturnType(),
    validIdentifier,
    ref0(functionArgDef).skip(before: char("("), after: char(")")),
    ref0(block)
  ).map4((rtype, name, args, body)=>FunctionDef(name, args, rtype, body));
  /*         === Function End ===           */

  /*          === When Start ===            */
  /// when green flag clicked
  Parser<OnEventContext> onEventFlag() // on flag {} 
    => string("flag").map((_)=>OnFlagClicked());
  /// when "any" key pressed
  Parser<OnEventContext> onEventKeyPress() // on key "any" {}
    => strings().skip(before: string("key").tokenSep())
      .map((key)=>OnKeyPressed(key.value));
  /// when I receive "message1"
  Parser<OnMessage> onEventMessage() // on message "message1" {}
    => strings().skip(before: string("message").tokenSep())
      .map((msg)=>OnMessage(msg.value));

  Parser<OnEvent> onEvent()
  => seq3(
    string("on").tokenSep(),
    (
      ref0(onEventFlag) |
      ref0(onEventKeyPress) |
      ref0(onEventMessage)
    ).cast<OnEventContext>(),
    ref0(block)
  ).map3((_, ctx, b)=>OnEvent(ctx, b));
  /*           === When End ===             */

  /*  ==== Top-Level Instructions End ====  */

  /* Motion */

  /* Events */
  Parser<Emit> emit() 
    => seq2(
      (char("!").optional() & string("emit")).trim().flatten(),
      (ref0(strings) | ref0(identifier)).cast<Expression>() 
    )
      .map2((estmt, s)=>Emit(s, !estmt.startsWith("!")));
  
  /* Controls */
  Parser<If> conditional()
    => seq4(
      string("if").trim(),
      ref0(expression).skip(before: char("("), after: char(")")),
      blockOrInlineInst,
      seq2(
        string("else").trim(),
        blockOrInlineInst
      ).map2((_,r)=>r).optional()
    ).map4((_, cond, b, eb)=>If(
      cond, 
      b,
      eb
    ));

  Parser<While> repeatUntil()
    => seq3(
      string("while").trim(),
      ref0(expression).skip(before: char("("), after: char(")")),
      blockOrInlineInst
    ).map3((_, cond, b)=>While(cond, b));

  Parser<Repeat> repeat()
    => seq3(
      string("repeat").trim(),
      ref0(expression),
      blockOrInlineInst
    ).map3((_, count, b)=>Repeat(count, b));

  Parser<Forever> forever()
    => seq2(
      string("forever").trim(),
      blockOrInlineInst
    ).map2((_, b)=>Forever(b));

  Parser<Sleep> sleep()
    => seq3(
      string("sleep").tokenSep(),
      string("until").tokenSep().optional(),
      ref0(expression)
    ).map3((_, until, e)=>Sleep(e, asSleepUntil: until != null));

  /* lore */
  Parser<Comment> comment() => [
    // Single-line
    seq2(
      (string("//") & char("/").optional()).trim(),
      pattern("\n\r").star().flatten()
    ).map2((_, c)=>c),
    // Multi-line
    seq2(
      string("/*").trim(),
      pattern("*").starLazy(string("*/")).flatten()
    ).map2((_, c)=>c)
  ].toChoiceParser().map((c)=>Comment(c));

  late final Parser<AST> instructions = [
    ref0(assignment),
    ref0(declaration),
    //ref0(block),

    ref0(conditional),
    ref0(repeatUntil),
    ref0(repeat),
    ref0(forever),
    ref0(sleep),

    ref0(emit)
  ].toChoiceParser();

  late final Parser<Block> blockOrInlineInst = [
    instructions.map((r)=>Block([r])),
    ref0(block)
  ].toChoiceParser();

  Parser<Block> block() => instructions.star().skip(before: char("{"), after: char("}")).map((e)=>Block(e));

  Parser<List<AST>> tlInstructions() => [
    ref0(declaration),
    ref0(function),
    ref0(onEvent)
  ].toChoiceParser().cast<AST>().star();
  /* ====== Instructions End ====== */

  @override
  Parser<List<AST>> start() => ref0(tlInstructions).end();
}
