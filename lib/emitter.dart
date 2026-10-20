import 'dart:math';

import 'package:kerf/ast.dart';
import 'package:kerf/semantics.dart';

const soup_ = '!#%()*+,-./:;=?@[]^_`{|}~' +
    'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';

String getRandomId() {
  final rand = Random();
  return List.generate(20, (_) => soup_[rand.nextInt(soup_.length)]).join();
}

typedef JsonMap = Map<String, dynamic>;


enum OutputTarget {scratch, penguin}

/// This is clanked
class ProjectEmitter {
  final OutputTarget outputTarget;
  final SemanticAnalyzer analyzer;

  late final SpriteEmitter stageTarget = StageEmitter(this);

  ProjectEmitter({
    required this.outputTarget, 
    required this.analyzer
  });
}

class StageEmitter extends SpriteEmitter {
  StageEmitter(super.project) : super(name: "Stage");

  @override
  JsonMap compile(List<AST> topLevelStatements) {
    final spriteData = super.compile(topLevelStatements);
    spriteData["isStage"] = true;
    return spriteData;
  }
}
class SpriteEmitter {
  final Map<String, dynamic> blocksMap = {};
  final Map<String, String> variableIds = {};
  final Map<String, String> broadcastIds = {};

  OutputTarget get target => project.outputTarget;

  final ProjectEmitter project;
  final String name;

  SpriteEmitter(this.project, {required this.name});

  JsonMap compile(List<AST> topLevelStatements) {
    compileTopLevelStatementList(topLevelStatements);


    final r = {
      "isStage": false,
      "name": name,
      "blocks": blocksMap,
      "comments": {},
      "lists": {}, 
      "variables": variableIds.map((n,i)=>MapEntry(i, [n,0])),
      "broadcasts": broadcastIds.map((n,i)=>MapEntry(i,n)),

      "volume": 100,
      "layerOrder": 0,
      "tempo": 60,
      "videoTransparency": 50,
      "videoState": "on",
      "textToSpeechLanguage": null
    };

    return r;
  }

  String registerVariable(String name) {
    final id = "${getRandomId()}-$name";
    variableIds[name] = id;
    return id;
  }

  String registerBroadcast(String name) {
    final id = getRandomId();
    broadcastIds[name] = id;
    return id;
  }

  /* ======== Blocks ======== */

  // Compiles a list of statements sequentially, linking their 'next' pointers.
  // Returns the ID of the very first block in the sequence.
  String? compileStatementList(List<AST> body, String? parentId, SymbolTable symbols) {
    String? firstBlockId;
    String? previousBlockId = parentId;

    for (var stmt in body) {
      String currentBlockId = compileStatement(stmt, previousBlockId, symbols);
      
      firstBlockId ??= currentBlockId;

      // Link the previous block's 'next' pointer to this current block
      if (previousBlockId != null && previousBlockId != parentId) {
        blocksMap[previousBlockId]['next'] = currentBlockId;
      }

      previousBlockId = currentBlockId;
    }
    return firstBlockId;
  }

  void compileTopLevelStatementList(List<AST> topLevelStatements) {
    int lastX = 0;
    for (final stmt in topLevelStatements) {
      lastX += compileTopLevelStatement(stmt, lastX);
    }
  }
  // y is forced to 36

  /// Same as [compileStatement] but for top-level statements, which don't have a parent block.
  /// Plus, handles placing them on the canvas
  /// Returns how much the next top level block should shift to the right 
  /// so that it doesnt overlap
  int compileTopLevelStatement(AST stmt, int lastX) {
    String blockId = getRandomId();
    int nextXOffset = 0;
    
    if (stmt is OnEvent) {
      final context = stmt.context;
      // Compile the event block
      blocksMap[blockId] = {
        "opcode": switch (context) {
          OnFlagClicked() => "event_whenflagclicked",
          OnKeyPressed() => "event_whenkeypressed",
          OnMessage() => "event_whenbroadcastreceived",
          _ => throw Exception("Unknown event context: $context")
        },
        "parent": null,
        "next": compileStatementList(stmt.body.body, blockId, project.analyzer.localScopes[stmt.body]!),
        "inputs": {},
        "fields": {
          if (context is OnKeyPressed) "KEY_OPTION": [context.key, null],
          if (context is OnMessage) "BROADCAST_OPTION": [context.message, null]
        }
      };

      nextXOffset = 100; 
    }
    else if (stmt is FunctionDef) {
      final prototypeId = getRandomId();

      // Definition block
      blocksMap[blockId] = {
        "opcode": "procedures_definition",
        "parent": null,
        "next": compileStatementList(stmt.body.body, blockId, project.analyzer.localScopes[stmt.body]!),
        "inputs": {
          "custom_block": [2, prototypeId]
        },
        "fields": {}
      };

      // Prototype block
      final funcSemantics = (project.analyzer.globalScope.lookup(stmt.name)! as FunctionSymbol);
      final argsSemantics = funcSemantics.argumentPos.map((k,v)=>MapEntry(k,funcSemantics.arguments[v]));

      final two = argsSemantics.map((k,v)=>MapEntry(k, (getRandomId(), v)));

      final reportersMap = argsSemantics.map((argName, argType) {
        final argId = two[argName]!.$1;
        final inp = compileExpressionAsInput(Identifier(argName), prototypeId, project.analyzer.localScopes[stmt.body]!);
        return MapEntry(argId, inp);
      });

      blocksMap[prototypeId] = {
        "opcode": "procedures_prototype",
        "parent": blockId,
        "next": null,
        "inputs": reportersMap, 
        "fields": {},

      };

      // Compile the body of the function

      nextXOffset = 100; // Increment x for next top-level block
    } 

    else {
      throw Exception("Unsupported top-level statement: $stmt");
    }

    // Positioning logic for top-level blocks
    blocksMap[blockId]["x"] = lastX;
    blocksMap[blockId]["y"] = 36; // Fixed y position for top-level blocks

    return nextXOffset;
  }

  String compileStatement(AST stmt, String? parentId, SymbolTable symbols) {
    String blockId = getRandomId();

    if (stmt is If) {
      // 1. Compile condition expression (which might be a literal or a reporter block)
      var conditionInput = compileExpressionAsInput(stmt.condition, blockId, symbols);
      
      // 2. Compile the "then" body statements recursively
      String? substackId = compileStatementList(stmt.thenBlock.body, blockId);

      blocksMap[blockId] = {
        "opcode": "control_if",
        "parent": parentId,
        "next": null,
        "inputs": {
          "CONDITION": conditionInput,
          if (substackId != null) "SUBSTACK": [2, substackId] // [2, id] points to a block reporter/stack
        },
        "fields": {}
      };
    } 
    // Handle other statements (Repeat, While, Forever, Assignments, etc.)
    
    return blockId;
  }


  /* ======== Blocks ======== */


  /* ======== Expressions ======== */

  /// Returns either a literal array or a [2, block_id] pointer for a reporter block
  List<dynamic> compileExpressionAsInput(Expression expr, String parentId, SymbolTable symbols) {
    // Case A: Literal values
    if (expr is IntLiteral) {
      return [1, [1, expr.value.toString()]]; // Scratch number literal format
    }
    
    if (expr is BoolLiteral) {
      if (target == .penguin) {
        // PenguinMod optimization: Emit native <true> or <false> reporter block!
        String reporterId = getRandomId();
        blocksMap[reporterId] = {
          "opcode": expr.value ? "operator_bool_true" : "operator_bool_false",
          "parent": parentId,
          "next": null,
          "inputs": {},
          "fields": {}
        };
        return [2, reporterId]; // [2, id] tells Scratch/PM to evaluate this block reporter
      } else {
        // Vanilla Scratch fallback: (1 = 1) for true, (1 = 0) for false
        String reporterId = getRandomId();
        blocksMap[reporterId] = {
          "opcode": "operator_equals",
          "parent": parentId,
          "next": null,
          "inputs": {
            "OPERAND1": [1, [1, "1"]],
            "OPERAND2": [1, [1, expr.value ? "1" : "0"]]
          },
          "fields": {}
        };
        return [2, reporterId];
      }
    }

    // Case B: Binary Expressions (Operators like +, -, *, /)
    if (expr is BinaryExpr) {
      String reporterId = getRandomId();
      var leftInput = compileExpressionAsInput(expr.left, reporterId, symbols);
      var rightInput = compileExpressionAsInput(expr.right, reporterId, symbols);

      blocksMap[reporterId] = {
        "opcode": _mapBinaryOpToOpcode(expr.op),
        "parent": parentId,
        "next": null,
        "inputs": {
          "NUM1": leftInput,
          "NUM2": rightInput
        },
        "fields": {}
      };
      return [2, reporterId];
    }

    // Case C: Identifiers
    if (expr is Identifier) {
      final symbol = symbols.lookup(expr.name);

      if (symbol is PrimitiveSymbol) {
        String reporterId = getRandomId();
        blocksMap[reporterId] = {
          "opcode": "data_variable",
          "parent": parentId,
          "next": null,
          "inputs": {},
          "fields": {
            "VARIABLE": [expr.name, symbol.type.toString()]
          }
        };
        return [2, reporterId];
      } else if (symbol is FunctionArgSymbol) {
        String reporterId = getRandomId();
        blocksMap[reporterId] = {
          "opcode": "argument_reporter_${symbol.type == .bool ? 'boolean' : 'string_number'}",
          "parent": parentId,
          "next": null,
          "inputs": {},
          "fields": {
            "VALUE": [expr.name, null]
          }
        };
        return [2, reporterId];
      } else {
        throw Exception("Unsupported identifier type for expression: ${expr.name}");
      }
    }

    // Default fallback
    return [1, [1, "0"]];
  }

  String _mapBinaryOpToOpcode(BinaryOperator op) {
    switch (op) {
      case BinaryOperator.plus: return "operator_add";
      case BinaryOperator.minus: return "operator_subtract";
      case BinaryOperator.multiply: return "operator_multiply";
      case BinaryOperator.divide: return "operator_divide";
      default: return "operator_add";
    }
  }

  /* ======== Expressions ======== */
}
