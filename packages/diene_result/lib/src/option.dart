import 'package:diene_problems/diene_problems.dart';

import 'result.dart';
import 'unwrap_error.dart';
import 'wire.dart';

/// A value that is either [Some] or [None].
sealed class Option<T> {
  const Option();

  const factory Option.some(T value) = Some<T>;

  const factory Option.none() = None<T>;

  /// Converts `null` to [None] and every other value to [Some].
  factory Option.fromNullable(T? value) =>
      value == null ? None<T>() : Some<T>(value);

  /// Decodes `['some', value]` or `['none', null]`; throws [FormatException].
  factory Option.fromSerial(
    OptionSerial serial, {
    required T Function(Object? value) decodeSome,
  }) {
    final (String tag, Object? value) = readTaggedWire(
      serial,
      monad: 'Option',
      tags: const <String>{'some', 'none'},
    );
    if (tag == 'none' && value != null) {
      throw const FormatException('Option none wire payload must be null.');
    }

    return tag == 'some' ? Some<T>(decodeSome(value)) : None<T>();
  }

  bool get isSome => this is Some<T>;

  bool get isNone => this is None<T>;

  Option<R> map<R>(R Function(T value) mapper) => switch (this) {
    Some<T>(:final value) => Some<R>(mapper(value)),
    None<T>() => None<R>(),
  };

  Option<R> andThen<R>(Option<R> Function(T value) mapper) => switch (this) {
    Some<T>(:final value) => mapper(value),
    None<T>() => None<R>(),
  };

  R match<R>({required R Function(T value) some, required R Function() none}) =>
      switch (this) {
        Some<T>(:final value) => some(value),
        None<T>() => none(),
      };

  /// Returns the [Some] value or throws [UnwrapError].
  T unwrap() => switch (this) {
    Some<T>(:final value) => value,
    None<T>() => throw UnwrapError(
      monad: MonadKind.option,
      expected: 'Some',
      actual: 'None',
    ),
  };

  T unwrapOr(T fallback) => switch (this) {
    Some<T>(:final value) => value,
    None<T>() => fallback,
  };

  T unwrapOrElse(T Function() fallback) => switch (this) {
    Some<T>(:final value) => value,
    None<T>() => fallback(),
  };

  /// Converts [Some] to [Ok] and [None] to [Err].
  Result<T> okOr(Problem problem) => switch (this) {
    Some<T>(:final value) => Ok<T>(value),
    None<T>() => Err<T>(problem),
  };

  /// Maps either option variant directly into a [Result].
  Result<R> asResult<R>({
    required Result<R> Function(T value) some,
    required Result<R> Function() none,
  }) => switch (this) {
    Some<T>(:final value) => some(value),
    None<T>() => none(),
  };

  /// Returns the nullable native representation.
  T? native() => switch (this) {
    Some<T>(:final value) => value,
    None<T>() => null,
  };

  OptionSerial serial({Object? Function(T value)? encodeSome}) =>
      switch (this) {
        Some<T>(:final value) => taggedWire(
          'some',
          encodeSome == null ? value : encodeSome(value),
        ),
        None<T>() => taggedWire('none', null),
      };
}

final class Some<T> extends Option<T> {
  const Some(this.value);

  final T value;

  @override
  String toString() => 'Some($value)';
}

final class None<T> extends Option<T> {
  const None();

  @override
  String toString() => 'None';
}

/// Converts an optional [Problem] into the error channel of a [Result].
extension ProblemOptionResult on Option<Problem> {
  /// Returns [Err] for [Some] and [Ok] with [value] for [None].
  Result<T> errOr<T>(T value) => switch (this) {
    Some<Problem>(:final value) => Err<T>(value),
    None<Problem>() => Ok<T>(value),
  };
}
