/// Dependency-light assertions for consumers of `package:diene_result`.
library;

import 'package:diene_problems/diene_problems.dart';

import 'diene_result.dart';

final class TestHelperFailure implements Exception {
  const TestHelperFailure(this.message);

  final String message;

  @override
  String toString() => 'TestHelperFailure: $message';
}

/// Requires [actual] to be [Ok] and returns its value for further assertions.
T expectOk<T>(Result<T> actual) => switch (actual) {
  Ok<T>(:final value) => value,
  Err<T>(:final problem) => throw TestHelperFailure(
    'Expected Ok, got Err carrying $problem.',
  ),
};

/// Requires [actual] to be [Err] and returns its problem.
Problem expectErr<T>(Result<T> actual) => switch (actual) {
  Ok<T>(:final value) => throw TestHelperFailure(
    'Expected Err, got Ok carrying $value.',
  ),
  Err<T>(:final problem) => problem,
};

/// Requires [actual] to be [Some] and returns its value.
T expectSome<T>(Option<T> actual) => switch (actual) {
  Some<T>(:final value) => value,
  None<T>() => throw const TestHelperFailure('Expected Some, got None.'),
};

/// Requires [actual] to be [None].
void expectNone<T>(Option<T> actual) {
  if (actual case Some<T>(:final value)) {
    throw TestHelperFailure('Expected None, got Some carrying $value.');
  }
}
