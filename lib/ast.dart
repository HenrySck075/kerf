
abstract class AST {
  int start = 0;
  int stop = 0;
}

/// Abstract base for all expression nodes.
abstract class Expression extends AST {}

/// Abstract base for literal values.
abstract class Literal extends Expression {}

class StringLiteral extends Literal {
  final String value;
  StringLiteral(this.value);
}

class BoolLiteral extends Literal {
  final bool value;
  BoolLiteral(this.value);
}

class NumLiteral extends Literal {
  final num value;
  NumLiteral(this.value);
}

class IntLiteral extends NumLiteral {
  IntLiteral(super.value);

  @override
  int get value => super.value.toInt();
}
class FloatLiteral extends NumLiteral {
  FloatLiteral(super.value);

  @override
  double get value => super.value.toDouble();
}

class ListLiteral extends Expression {
  final List<Expression> elements;
  final String? explicitTypeName;

  ListLiteral(this.elements, [this.explicitTypeName]);
}

enum FactorOp { positive, negative }

class Factor extends Expression {
  final FactorOp op;
  final Expression operand;

  Factor(this.op, this.operand);
}

class Power extends Expression {
  final Expression base;
  final Expression exponent;

  Power(this.base, this.exponent);
}

enum BinaryOperator {
  plus,
  minus,
  multiply,
  divide,
  divideInt,
  modulo,
}

class TwoHandedExpression extends Expression {
  final Expression left;
  final Expression right;

  TwoHandedExpression(this.left, this.right);
}
class BinaryExpr extends TwoHandedExpression {
  final BinaryOperator op;

  BinaryExpr(super.left, this.op, super.right);
}

class IndexAccess extends Expression {
  final Expression target;
  final Expression key;

  IndexAccess(this.target, this.key);
}

class Inversion extends Expression {
  final Expression operand;

  Inversion(this.operand);
}

class Conjunction extends TwoHandedExpression {
  Conjunction(super.left, super.right);
}

class Disjunction extends TwoHandedExpression {
  Disjunction(super.left, super.right);
}

class Identifier extends Expression {
  final String name;

  Identifier(this.name);
}

// Special Expressions
enum SPEProperty {x, y, rotation}
class SpritePositionExpr extends Expression {
  final SPEProperty property;

  SpritePositionExpr(this.property);
}

enum TouchTarget {mouse, edge, sprite}
class TouchingExpr extends Expression {
  final TouchTarget target;
  final String? spriteId; // lets just leave it here

  TouchingExpr(this.target, [this.spriteId]);
}

//////////////////////////
// Statements & Program Constructs
//////////////////////////

class Block extends AST {
  final List<AST> body;

  Block(this.body);
}

class Comment extends AST {
  final String text;

  Comment(this.text);
}

/* Top-Level Instructions */

class Assignment extends AST {
  final String name;
  final Expression value;
  final bool isConst;

  Assignment(this.name, this.value, [this.isConst = false]);
}

class Declaration extends Assignment {
  Declaration(super.name, super.value, [super.isConst]);
}

class Argument extends AST {
  final String? name;
  final Expression value;

  Argument(this.value, {this.name});
}

class FunctionCall extends Expression {
  final String name;
  final List<Argument> arguments;

  FunctionCall(this.name, this.arguments);
}

class ArgumentDef extends AST {
  final String name;
  final String typeName;

  ArgumentDef(this.name, this.typeName);
}

class FunctionDef extends AST {
  final String name;
  final List<ArgumentDef> arguments;
  final String returnTypeName;
  final Block body;

  FunctionDef(
    this.name,
    this.arguments,
    this.returnTypeName,
    this.body,
  );
}


/* Event */
abstract class OnEventContext {}

class OnFlagClicked extends OnEventContext {}

class OnKeyPressed extends OnEventContext {
  final String key;

  OnKeyPressed(this.key);
}

class OnMessage extends OnEventContext {
  final String message;

  OnMessage(this.message);
}

class OnEvent extends AST {
  final OnEventContext context;
  final Block body;

  OnEvent(this.context, this.body);
}


class Emit extends AST {
  final Expression message;
  final bool wait;

  Emit(this.message, this.wait);
}


/* Controls */
class If extends AST {
  final Expression condition;
  final Block thenBlock;
  final Block? elseBlock;

  If(this.condition, this.thenBlock, [this.elseBlock]);
}

class Repeat extends AST {
  final Expression count;
  final Block body;

  Repeat(this.count, this.body);
}

/// aka repeat until
class While extends AST {
  final Expression condition;
  final Block body;

  While(this.condition, this.body);
} 

class Forever extends AST {
  final Block body;

  Forever(this.body);
}

class Sleep extends AST {
  final Expression instruction;
  final bool asSleepUntil;
  
  Sleep(this.instruction, {this.asSleepUntil = false});
}
