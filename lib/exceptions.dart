class NameError implements Exception {
  final String variableName;
  NameError(this.variableName);

  @override
  String toString() => 'NameError: Variable "$variableName" is not defined.';
}

class TypeError implements Exception {
  final String message;
  TypeError(this.message);

  @override
  String toString() => 'TypeError: $message';
}
