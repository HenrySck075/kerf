import 'package:kerf/ast.dart';
import 'package:test/test.dart'; // or package:test/test.dart
import 'package:petitparser/petitparser.dart';
import 'package:kerf/grammar.dart';

void main() {
  late Parser listParser;
  late Parser expressionParser;

  setUp(() {
    final definition = KerfGrammarDefinition();
    // This isolates just the list rule for targeted unit testing!
    listParser = definition.buildFrom(definition.list());
    expressionParser = definition.buildFrom(definition.expression());
  });

  group("(Mathematical) Expressions", () {
    test('random math operations', () {
      final result = expressionParser.parse('1+2/3-6');

      expect(result is Success && result.value is Term, isTrue);

      final valueCasted = result.value as Term;

      expect(valueCasted.op == .minus, isTrue);
      final l = (valueCasted.left as Term);
      expect(l.op == .plus, isTrue);
      final lr = (l.right as Term);
      expect(lr.op == .divide, isTrue);
    });

    test('random math operations but with group parens', () {
      final result = expressionParser.parse('(1+2)/3-6');

      expect(result is Success && result.value is Term, isTrue);

      final valueCasted = result.value as Term;

      expect(valueCasted.op == .minus, isTrue);
      final l = (valueCasted.left as Term);
      expect(l.op == .divide, isTrue);
      final ll = (l.left as Term);
      expect(ll.op == .plus, isTrue);

    });
  });

  group('List Parser Tests', () {
    test('successfully parses a plain integer list', () {
      final result = listParser.parse('[1, 2, 3]');
      
      expect(result is Success, isTrue);
      
      final List_ listAst = result.value;
      expect(listAst.elements.length, equals(3));
      expect(listAst.elementType, equals(AtomType.int));
    });

    test('successfully parses a typed string list', () {
      final result = listParser.parse('<string>["apple", "banana"]');
      
      expect(result is Success, isTrue);
      
      final List_ listAst = result.value;
      expect(listAst.elementType, equals(AtomType.string));
    });

    test('fails gracefully on missing closing bracket', () {
      final result = listParser.parse('<int>[1, 2, 3');
      
      expect(result is Failure, isTrue);
      // You can even assert where it failed
      expect(result.position, equals(13)); 
    });
  });
}
