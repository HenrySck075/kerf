import 'package:kerf/ast.dart';
import 'package:kerf/semantics.dart';
import 'dart:math';

const soup_ = '!#%()*+,-./:;=?@[]^_`{|}~' +
    'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';

String getRandomId() {
  final rand = Random();
  return List.generate(20, (_) => soup_[rand.nextInt(soup_.length)]).join();
}

typedef JsonMap = Map<String, dynamic>;



enum Target {scratch, penguin}

class Emitter {
  final Target outputTarget;

  Emitter(this.outputTarget);

  // Map<funcName, Map<argName, argId>>
  final Map<String, Map<String, String>> _functionIdLookup = {};
  SemanticAnalyzer? _analyzer;

  String jsonEncodeIterable(Iterable<String> iterable) {
    return '[' + iterable.map((e) => '"$e"').join(',') + ']';
  }

  Iterable<(String, JsonMap)> emitBlocks(List<AST> instructions, SymbolTable symbols, {bool topLevel = false, String? parentId}) sync* {
    (String, JsonMap)? previousObj;
    (String, JsonMap) i(JsonMap obj) {
      final id = getRandomId();
      obj.putIfAbsent("next", ()=> null);
      
      if (previousObj != null) {
        previousObj!.$2["next"] = id;
        obj["parent"] = previousObj!.$1;
      }
      if (obj["parent"] == null) {
        obj["parent"] = parentId;
      }

      obj.putIfAbsent("inputs", ()=> {});
      obj.putIfAbsent("fields", ()=> {});
      previousObj = (id, obj);
      return (id, obj);
    }
    for (final node in instructions) {
      switch (node) {
        /// Top-Level Instructions
        case OnEvent(:final context, :final body):
          yield i({
            "opcode": switch (context) {
              OnFlagClicked _ => "event_whenflagclicked",
              OnKeyPressed _ => "event_whenkeypressed",
              OnMessage _ => "event_whenbroadcastreceived",
              _ => throw Exception("Unknown event context: $context")
            },
            "shadow": false,
            "topLevel": true
          });
          
          yield* emitBlocks(body.body, _analyzer!.localScopes[body]!, parentId: previousObj!.$1);

        case FunctionDef(:final name, :final arguments, :final body):
          final argIdLookup = <String, String>{};
          for (final arg in arguments) {
            argIdLookup[arg.name] = getRandomId();
          }
          _functionIdLookup[name] = argIdLookup;

          yield i({
            "opcode": "procedures_prototype",
            "shadow": false,
            "topLevel": true,
            "mutation": {
              "tagName": "mutation",
              "children": [],
              "proccode": "$name ${arguments.map((arg) => "<${arg.name}>").join(" ")}",
              "argumentids": jsonEncodeIterable(arguments.map((arg) => argIdLookup[arg.name]!)),
              "argumentnames": jsonEncodeIterable(arguments.map((arg) => arg.name)),
              "argumentdefaults": jsonEncodeIterable(arguments.map((arg) =>
                switch (arg.typeName) {
                  "int" => "",
                  "float" => "",
                  "string" => "",
                  "bool" => "false",
                  _ => throw Exception("Unknown/Unsupported argument type: ${arg.typeName}")
                }
                )),
              "warp": false
            }
          });

          yield* emitBlocks(body.body, _analyzer!.localScopes[body]!, parentId: previousObj!.$1);
      }

      if (topLevel) previousObj = null;
    }

    return;
  }

  JsonMap emitTargetObject(List<AST> tlInst, SemanticAnalyzer analyzer) {
    _analyzer = analyzer;
    final obj = {
      "isStage": false,
      "name": "Sprite1",
      "variables": {},
      "lists": {},
      "broadcasts": {},
      "blocks": {}
    };

    _analyzer = null;

    return obj;
  }
}
