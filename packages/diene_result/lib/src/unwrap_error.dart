enum MonadKind { result, option }

/// Thrown only when an explicit unwrap asks for the wrong variant.
final class UnwrapError extends StateError {
  UnwrapError({
    required this.monad,
    required this.expected,
    required this.actual,
    this.payload,
  }) : super('Expected $expected, got $actual.');

  final MonadKind monad;

  final String expected;

  final String actual;

  /// Payload carried by the actual variant, when one exists.
  final Object? payload;

  @override
  String toString() =>
      'UnwrapError(monad: ${monad.name}, expected: $expected, '
      'actual: $actual, payload: $payload)';
}
