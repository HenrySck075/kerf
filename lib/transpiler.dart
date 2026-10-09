import 'package:kerf/ast.dart';
import 'package:kerf/grammar.dart';

abstract class SymbolType {}

enum PrimitiveType { str, int, bool, float, list }
class PrimitiveSymbol extends SymbolType {
  PrimitiveType type;

  PrimitiveSymbol(this.type);
}

class FunctionSymbol extends SymbolType {
  PrimitiveType returnType;
  List<PrimitiveType> arguments;
  Map<String, int> argumentPos; // for named lookup

  FunctionSymbol(this.returnType, this.arguments, this.argumentPos);
}

class SymbolTable {
  final Map<String, SymbolType> _symbols = {};
  final SymbolTable? parent;

  SymbolTable([this.parent]);

  void declare(String name, SymbolType type) => _symbols[name] = type;

  SymbolType? lookup(String name) => _symbols[name] ?? parent?.lookup(name);
}

class SemanticAnalyzer {
  final SymbolTable globalScope = SymbolTable();
  final Map<Block, SymbolTable> localScopes = {};

  SymbolType _analyzeExpression(Expression expr) {
    // primitives
    if (expr is StringLiteral) {
      return PrimitiveSymbol(.str);
    } else if (expr is IntLiteral) {
      return PrimitiveSymbol(.int); 
    } else if (expr is FloatLiteral) {
      return PrimitiveSymbol(.float); 
    } else if (expr is BoolLiteral) {
      return PrimitiveSymbol(.bool);
    } else if (expr is ListLiteral) {
      return PrimitiveSymbol(.list);
    } else if (expr is Identifier) {
      final symbol = globalScope.lookup(expr.name);
      if (symbol == null) {
        throw Exception("Undefined identifier: ${expr.name}");
      }
      return symbol;
    } else if (expr is FunctionCall) {
      final symbol = globalScope.lookup(expr.name);
      if (symbol is! FunctionSymbol) {
        throw Exception("Undefined function: ${expr.name}");
      }
      // Check argument types
      if (expr.arguments.length != symbol.arguments.length) {
        throw Exception("Argument count mismatch for function: ${expr.name}");
      }
      for (var i = 0; i < expr.arguments.length; i++) {
        final argType = _analyzeExpression(expr.arguments[i].value);
        if (argType is! PrimitiveSymbol || argType.type != symbol.arguments[i]) {
          throw Exception("Argument type mismatch for function: ${expr.name}");
        }
      }
      return PrimitiveSymbol(symbol.returnType);
    } 

    // arithmetic operations
    else if (expr is BinaryExpr) {
      final leftType = _analyzeExpression(expr.left);
      final rightType = _analyzeExpression(expr.right);
      if (leftType is! PrimitiveSymbol || rightType is! PrimitiveSymbol) {
        throw Exception("Invalid operand types for binary expression");
      }

      // String + String -> String (concatenation)
      if (expr.op == .plus &&
          leftType.type == .str &&
          rightType.type == .str) {
        return PrimitiveSymbol(.str);
      }
      // String * int -> String (duplication)
      // in this exact order only
      else if (expr.op == .multiply &&
          leftType.type == .str &&
          rightType.type == .int) {
        return PrimitiveSymbol(.str);
      }
      // the rest on numerical operands
      else if (expr.op == .divideInt) {
        return PrimitiveSymbol(.int);
      }
      else if (leftType.type == .int &&
          rightType.type == .int) {
        return PrimitiveSymbol(.int);
      } 
      else if ((leftType.type == .int ||
              leftType.type == .float) &&
          (rightType.type == .int ||
              rightType.type == .float)) {
        return PrimitiveSymbol(.float);
      } else {
        throw Exception(
            "Invalid operand types for ${expr.op.name} expression: ${leftType.runtimeType} and ${rightType.runtimeType}");
      }
    }

    // other expressions
    else if (expr is IndexAccess) {
      final targetType = _analyzeExpression(expr.target);
      final keyType = _analyzeExpression(expr.key);
      if (targetType is! PrimitiveSymbol || targetType.type != .list) {
        throw Exception("Indexing is only supported on lists");
      }
      if (keyType is! PrimitiveSymbol || keyType.type != .int) {
        throw Exception("List indices must be integers");
      }
      // TODO: store list type
      return PrimitiveSymbol(.str); 
    }

    else if (expr is Inversion) {
      final operandType = _analyzeExpression(expr.operand);
      if (operandType is! PrimitiveSymbol || operandType.type != .bool) {
        throw Exception("Inversion is only supported on boolean expressions");
      }
      return PrimitiveSymbol(.bool);
    } else if (expr is Conjunction || expr is Disjunction) {
      final thexpr = expr as TwoHandedExpression;
      final leftType = _analyzeExpression(thexpr.left);
      final rightType = _analyzeExpression(thexpr.right);
      if (leftType is! PrimitiveSymbol || leftType.type != .bool ||
          rightType is! PrimitiveSymbol || rightType.type != .bool) {
        throw Exception("Logical operations are only supported on boolean expressions");
      }
      return PrimitiveSymbol(.bool);
    }

    else {
      throw Exception("Unsupported expression type: ${expr.runtimeType}");
    }
  }

  PrimitiveType _typeNameToEnum(String type) {
    switch (type) {
      case "str":
        return .str;
      case "int":
        return .int;
      case "bool":
        return .bool;
      case "float":
        return .float;
      case "list":
        return .list;
      default:
        throw Exception("Unknown type: $type");
    }
  }

  void analyze(AST node, SymbolTable symbols) {
    switch (node) {
      case Block(:final body): {
        for (final stmt in body) {
          analyze(stmt, symbols);
        }
      }
      case FunctionDef(
        :final returnTypeName,
        :final arguments,
        :final name
        // TODO: check if the body actually returns the correct type
      ): {
        final returnType = _typeNameToEnum(returnTypeName);
        final argTypes = arguments.map((arg) => _typeNameToEnum(arg.typeName)).toList();
        final argPos = {for (var i = 0; i < arguments.length; i++) arguments[i].name: i};
        symbols.declare(name, FunctionSymbol(returnType, argTypes, argPos));
        final localScope = SymbolTable(symbols);
        localScopes[node.body] = localScope;
        for (final arg in arguments) {
          localScope.declare(arg.name, PrimitiveSymbol(_typeNameToEnum(arg.typeName)));
        }
        analyze(node.body, localScope);
      }
      case Assignment(:final name, :final value): {
        final valueType = _analyzeExpression(value);
        symbols.declare(name, valueType);
      }
    }
  }
}



class FileTranspiler {
  final SemanticAnalyzer analyzer = SemanticAnalyzer();

  void transpile(String content, {bool forPenguin = false}) {
    final ast = KerfGrammarDefinition().build().parse(content);

    // pass 1: declare all FunctionDef nodes first
    for (final node in ast.value) {
      if (node is FunctionDef) {
        analyzer.analyze(node, analyzer.globalScope);
      }
    }
  }
}
