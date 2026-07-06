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
  final Map<String, AtomType> primitives = Map.fromEntries(AtomType.values.map((e)=>MapEntry(e.name, e)));
  late final Parser primitiveRule = [for (final p in primitives.keys) string(p)].toChoiceParser();

  /* ====== Expressions Start ====== */
  Parser<Num> number() => (_float | _int).trim().map((e)=>Num(num.parse(e)));
  Parser slString() => (_slString("'") | _slString('"')).flatten().trim();
  Parser mlString() => (_mlString("'") | _mlString('"')).flatten().trim();
  Parser<String_> strings() => (mlString() | slString()).trim().map((e)=>String_(e));
  Parser<Bool> boolean() => (string("true") | string("false")).trim().map((e)=>Bool(e=="true"));
  Parser<List_> list() => seq2( 
    primitiveRule.skip(before: char("<"), after: char(">")).optional().skip(after: char("[")),
    (ref(atom).starSeparated(char(",").trim())).skip(after: char("]"))
  ).trim().map2((optionalType, e)=>List_(e.elements.cast(), primitives[optionalType]));
  Parser<Atom> atom() => (ref(strings) | ref(boolean) | ref(number) | ref(list) | ref(expression)).cast<Atom>();
  Parser<Atom> primary() => (
    // grouping
    ref(expression).skip(before: char("("), after: char(")")) |

    ref(atom) |
    // sequence accessor
    seq2(ref(expression), ref(expression).skip(before:char("["),after:char("]"))).map2((v,key)=>SBAccessor(v,key)) 
  ).cast();

  Parser<AST> expression() {
    final builder = ExpressionBuilder<Atom>();
    
    builder.primitive(ref(primary));
    
    builder.group().right(
      char('^').trim(), (left, operator, right) => Power(left, right));

    builder.group()
      ..prefix(char("+"), (_,atom)=>Factor(.positive, atom))
      ..prefix(char("-"), (_,atom)=>Factor(.negative, atom));

    builder.group()
      ..left(char('*').trim(), (left, operator, right) => Term(left, .multiply, right))
      ..left(char('/').trim(), (left, operator, right) => Term(left, .divide, right))
      ..left(char('%').trim(), (left, operator, right) => Term(left, .modulo, right));
    builder.group()
      ..left(char('+').trim(), (left, operator, right) => Term(left, .plus, right))
      ..left(char('-').trim(), (left, operator, right) => Term(left, .minus, right));

    builder.group().prefix(char("!"), (_, a)=>Inversion(a));
    builder.group().left(string("&&"), (l, _, r)=>Conjunction(l,r));
    builder.group().left(string("||"), (l, _, r)=>Disjunction(l,r));

    return builder.build();
  }

  @override
  Parser<dynamic> start() => ref(expression).end();
  /* ====== Expressions End ====== */
}
