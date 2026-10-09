import 'package:kerf/ast.dart';
import 'package:petitparser/petitparser.dart';

class KerfGrammarDefinition extends GrammarDefinition {
  /* ====== Utils Start ====== */
  final Parser _escape = char('\\') & any();
  Parser _string(String wrapChar, String a) => string(wrapChar) & (_escape | noneOf(wrapChar+a).star()) & string(wrapChar);
  Parser _slString(String wrapChar) => _string(wrapChar,"\n\r");
  Parser _mlString(String wrapChar) => _string(wrapChar*3, "");
  
  final Parser _int = digit().plus().flatten().trim();
  final Parser _float = (digit().star() & char(".") & digit().plus()).flatten().trim();

  /* ====== Utils End ====== */
  late final Parser primitiveRule_ = [
    for (final p in ["str", "int", "bool", "float"]) string(p)
  ].toChoiceParser();
  Parser primitiveRule() => primitiveRule_ | string("list");

  /* ====== Expressions Start ====== */
  Parser<NumLiteral> number() => (
    _float.trim().map((e)=>FloatLiteral(double.parse(e))) |
    _int.trim().map((e)=>IntLiteral(int.parse(e)))
  ).cast();
  Parser slString() => (_slString("'") | _slString('"')).flatten().trim();
  Parser mlString() => (_mlString("'") | _mlString('"')).flatten().trim();
  Parser<StringLiteral> strings() => (mlString() | slString()).trim().map((e)=>StringLiteral(e));
  Parser<BoolLiteral> boolean() => (string("true") | string("false")).trim().map((e)=>BoolLiteral(e=="true"));
  Parser<ListLiteral> list() => seq2( 
    primitiveRule_.skip(before: char("<"), after: char(">")).optional().skip(after: char("[")),
    (ref0(atom).starSeparated(char(",").trim())).skip(after: char("]"))
  ).trim().map2((optionalType, e)=>ListLiteral(e.elements.cast(), optionalType));
  Parser<Expression> atom() => (ref0(strings) | ref0(boolean) | ref0(number) | ref0(list) | ref0(expression)).cast<Expression>();
  Parser<Expression> primary() => (
    // grouping
    ref0(expression).skip(before: char("("), after: char(")")) |

    ref0(atom) |
    // sequence accessor
    seq2(ref0(expression), ref0(expression).skip(before:char("["),after:char("]"))).map2((v,key)=>IndexAccess(v,key)) |
    // function calla
    seq2(validIdentifier, ref0(arguments).skip(before: char("("), after: char(")")))
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

    return builder.build();
  }
  /* ====== Expressions End ====== */

  
  /* ====== Instructions Start ====== */
  /*    ==== Assignment Start ====    */
  final Parser<String> validIdentifier = (pattern("a-zA-Z_") & pattern("a-zA-Z0-9_").star()).trim().flatten();
  Parser<R> terminator<R>(Parser<R> parser) => parser.skip(after: char(";")).trim();

  Parser<(String, Expression)> namedArgument() => seq2(validIdentifier.skip(after: char("=").trim()), ref0(expression));
  Parser<Argument> argument() => (
    ref0(expression).map((v)=>Argument(v)) | 
    ref0(namedArgument).map((t)=>Argument(t.$2, name: t.$1))
  ).cast();
  Parser<List<Argument>> arguments() => ref0(argument).starSeparated(char(",")).map((e)=>e.elements.cast<Argument>());

  Parser<AST> assignment() 
  => terminator(ref0(namedArgument))
    .map((t)=>Assignment(t.$1, t.$2));
  /*     ==== Assignment End ====     */

  /* ==== Top-Level Instructions Start ==== */
  /*        === Function Start ===          */
  Parser<List<ArgumentDef>> functionArgDef() 
  => seq2(
    validIdentifier.skip(after: char(":").trim()),
    primitiveRule().optional()
  ).map2((name, type)=>ArgumentDef(name, type)).cast<ArgumentDef>().starSeparated(char(",")).map((e)=>e.elements.cast<ArgumentDef>());

  Parser<AST> function() 
  => seq4(
    primitiveRule(),
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
    => strings().skip(before: string("key") & whitespace())
      .map((key)=>OnKeyPressed(key.value));
  /// when I receive "message1"
  Parser<OnMessage> onEventMessage() // on message "message1" {}
    => strings().skip(before: string("message") & whitespace())
      .map((msg)=>OnMessage(msg.value));

  Parser<AST> onEvent()
  => seq3(
    string("on").trim(),
    (
      ref0(onEventFlag) |
      ref0(onEventKeyPress) |
      ref0(onEventMessage)
    ).cast<OnEventContext>(),
    ref0(block)
  ).map3((_, ctx, b)=>OnEvent(ctx, b));
  /*           === When End ===             */

  
  late final List<Parser<AST>> instructions = [
    ref0(assignment),
    ref0(block)
  ];
  Parser<Block> block() => instructions.toChoiceParser().cast<AST>().star().skip(before: char("{"), after: char("}")).map((e)=>Block(e));
  Parser<List<AST>> tlInstructions() => [ref0(function)].toChoiceParser().cast<AST>().star();
  /* ====== Instructions End ====== */

  @override
  Parser<List<AST>> start() => ref0(tlInstructions).end();
}
