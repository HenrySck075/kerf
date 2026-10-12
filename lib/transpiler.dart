import 'package:kerf/grammar.dart';
import 'package:kerf/semantics.dart';



class FileTranspiler {
  final SemanticAnalyzer analyzer = SemanticAnalyzer();

  void transpile(String content, {bool forPenguin = false}) {
    final ast = KerfGrammarDefinition().build().parse(content);

    /// special variables
    analyzer.globalScope.declare("spriteX", PrimitiveSymbol(.float));
    analyzer.globalScope.declare("spriteY", PrimitiveSymbol(.float));
    analyzer.globalScope.declare("spriteRot", PrimitiveSymbol(.float));

    for (final node in ast.value) {
      analyzer.analyze(node, analyzer.globalScope);
    }
  }
}
