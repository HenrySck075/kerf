import 'dart:math' as math;

class SyntaxError extends Error {
  final String message;
  SyntaxError(this.message);

  @override
  String toString() => "SyntaxError: $message";
}

class AST {
  int line = 0;
  int col = 0;
}

enum AtomType {
  string, boolean, float, int, list
}

// Every expression syntax is under Atom
abstract class Atom extends AST {
  AtomType get type;

  /// Return a new [Atom] that yields the same result as this one, but with fewer instructions. May returns itself.
  Atom staticOptimize() => this;

  AtomType get childType => type;
}

abstract class Literal extends Atom {
  bool isTruthy();
}

// ignore: camel_case_types
class String_ extends Literal {
  final String value;
  String_(this.value);

  @override
  AtomType get type => .string;

  @override
  bool isTruthy() => value.isNotEmpty; 
}

class Bool extends Literal {
  final bool value;
  Bool(this.value);

  @override
  AtomType get type => .boolean;

  @override
  bool isTruthy() => value; 
}

class Num extends Literal {
  final num value;
  Num(this.value);

  @override
  AtomType get type => value is double ? .float : .int;

  @override
  bool isTruthy() => value != 0; 
}

// ignore: camel_case_types
class List_ extends Atom {
  final List<Atom> elements;
  final AtomType elementType;

  List_(this.elements, AtomType? elementType) 
  // we do list like c++ for now, sorry
  // aka every elements must be of the same type
  : assert(elements.isEmpty || elements.every((e) => e.type == elements.first.type), "All elements of a list must be of the same type.")
  , assert((elementType == null || elements.isEmpty) || elementType == elements.first.type, "Explicit element type declaration must match the actual type of the elements.")
  , elementType = elementType ?? elements.first.type;

  @override
  AtomType get type => .list;

  @override
  Atom staticOptimize() {
    return List_(elements.map((e) => e.staticOptimize()).toList(), elementType);
  }

  @override
  AtomType get childType => elementType;
}

/* Every parameters should be Atom, precise type should be checked via the AtomType enum. */

enum FactorOp {
  positive, negative;
}
class Factor extends Atom {
  final FactorOp op;
  final Atom atom;

  Factor(this.op, this.atom)
  : assert(atom.type == .float || atom.type == .int, "Factor can only be applied to numbers.");

  @override
  AtomType get type => atom.type;

  @override
  Atom staticOptimize() {
    final oAtom = atom.staticOptimize() as Num;
    switch (op) {
      case FactorOp.positive:
        return oAtom;
      case FactorOp.negative:
        return Num(-oAtom.value);
    }
  }
}

class Power extends Atom {
  final Atom base;
  final Atom exponent;

  Power(this.base, this.exponent)
  : assert(
    (base.type == .float || base.type == .int) && 
    (exponent.type != .float && exponent.type != .int)
  , "Both base and exponent must be numbers.");

  @override
  AtomType get type => base.type == .int && exponent.type == .int ? .int : .float;

  @override
  Atom staticOptimize() {
    final oBase = base.staticOptimize();
    final oExponent = exponent.staticOptimize();

    if (oBase is Num && oExponent is Num) {
      return Num(math.pow(oBase.value, oExponent.value));
    }
    return Power(oBase, oExponent);
  }
}

enum Operator {
  plus,minus,multiply,divide,divideInt,modulo
}

class Term extends Atom {
  final Atom left;
  final Operator op;
  final Atom right;

  Term(this.left, this.op, this.right)
  : assert((){
    if (
      (
        (left.type == .float || left.type == .int) && 
        (right.type != .float && right.type != .int)
      ) || 
      (left.type == .boolean || right.type == .boolean)
    ) {
      throw SyntaxError("Unsupported operands: ${left.type.name} and ${right.type.name}");
    }
    if (left.type == .string) {
      if (op == .plus && right.type != .string) {
        throw SyntaxError("Can only concatenate string (not ${right.type.name}) to string");
      }
      else if (op == .multiply && right.type != .int) {
        throw SyntaxError("Can't multiply string by non-int of type ${right.type.name}");
      }
    }
    if (left.type == .list && right.type != .list) {
      throw SyntaxError("Can only concatenate list (not ${right.type.name}) to list");
    }

    return true;
  }());  

  @override
  AtomType get type => left.type;
}

class SBAccessor extends Atom {
  final Atom atom;
  final Atom key;

  SBAccessor(this.atom, this.key)
  : assert(
    (atom.type == .list || atom.type == .string) && key.type == .int,
    "Cannot access ${atom.type.name} with ${key.type.name} key"
  );
  
  @override
  AtomType get type => atom.childType;
}

class Inversion extends Atom {
  final Atom atom;

  Inversion(this.atom);

  @override
  AtomType get type => .boolean;

  @override
  Atom staticOptimize() {
    final oAtom = atom.staticOptimize();
    if (oAtom is Literal) {
      return Bool(!oAtom.isTruthy());
    }
    return this;
  }
}

class Conjunction extends Atom {
  final Atom left;
  final Atom right;

  Conjunction(this.left, this.right);

  @override
  AtomType get type => .boolean;

  @override
  Atom staticOptimize() {
    final oLeft = left.staticOptimize();
    if (oLeft is Literal && !oLeft.isTruthy()) {
      return Bool(false);
    }
    final oRight = right.staticOptimize();
    if (oRight is Literal && !oRight.isTruthy()) {
      return Bool(false);
    }
    if (oLeft is Literal && oRight is Literal) {
      return Bool(oLeft.isTruthy() && oRight.isTruthy());
    }
    return Conjunction(oLeft, oRight);
  }
}

class Disjunction extends Atom {
  final Atom left;
  final Atom right;

  Disjunction(this.left, this.right);

  @override
  AtomType get type => .boolean;

  @override
  Atom staticOptimize() {
    final oLeft = left.staticOptimize();
    if (oLeft is Literal && oLeft.isTruthy()) {
      return Bool(true);
    }
    final oRight = right.staticOptimize();
    if (oRight is Literal && oRight.isTruthy()) {
      return Bool(true);
    }
    if (oLeft is Literal && oRight is Literal) {
      return Bool(oLeft.isTruthy() && oRight.isTruthy());
    }
    return Conjunction(oLeft, oRight);
  }
}
