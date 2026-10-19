import 'package:kerf/grammar.dart';
import 'package:kerf/semantics.dart';
import 'package:kerf/ir.dart' as ir;
import 'package:kerf/ast.dart';

class FileTranspiler {
  final SemanticAnalyzer analyzer = SemanticAnalyzer();

  void transpile(String content, {bool forPenguin = false}) {
    final ast = KerfGrammarDefinition().build().parse(content);

    for (final node in ast.value) {
      analyzer.analyze(node, analyzer.globalScope);
    }


  }

  Sprite constructIR(List<AST> tlNodes) {
    final s = ir.Sprite();


  }
}
