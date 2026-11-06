import 'dart:async';

import 'package:diene_problems/diene_problems.dart';

import 'option.dart';
import 'unwrap_error.dart';
import 'wire.dart';

/// A value that is either [Ok] or [Err].
sealed class Result<T> {
  const Result();

  const factory Result.ok(T value) = Ok<T>;

  const factory Result.err(Problem problem) = Err<T>;

  /// Decodes `['ok', value]` or `['err', problem]`; throws [FormatException].
  factory Result.fromSerial(
    ResultSerial serial, {
    required T Function(Object? value) decodeOk,
    Problem Function(Object? value)? decodeErr,
  }) {
    final (String tag, Object? value) = readTaggedWire(
      serial,
      monad: 'Result',
      tags: const <String>{'ok', 'err'},
    );

    if (tag == 'ok') {
      return Ok<T>(decodeOk(value));
    }

    return Err<T>((decodeErr ?? _decodeProblem)(value));
  }

  bool get isOk => this is Ok<T>;

  bool get isErr => this is Err<T>;

  Result<R> map<R>(R Function(T value) mapper) => switch (this) {
    Ok<T>(:final value) => Ok<R>(mapper(value)),
    Err<T>(:final problem) => Err<R>(problem),
  };

  Result<T> mapErr(Problem Function(Problem problem) mapper) => switch (this) {
    Ok<T>(:final value) => Ok<T>(value),
    Err<T>(:final problem) => Err<T>(mapper(problem)),
  };

  Result<R> andThen<R>(Result<R> Function(T value) mapper) => switch (this) {
    Ok<T>(:final value) => mapper(value),
    Err<T>(:final problem) => Err<R>(problem),
  };

  R match<R>({
    required R Function(T value) ok,
    required R Function(Problem problem) err,
  }) => switch (this) {
    Ok<T>(:final value) => ok(value),
    Err<T>(:final problem) => err(problem),
  };

  /// Runs an [Ok]-side effect without capturing exceptions.
  Result<T> run(void Function(T value) sideEffect) {
    if (this case Ok<T>(:final value)) {
      sideEffect(value);
    }

    return this;
  }

  /// Runs an [Ok]-side effect and explicitly maps a thrown object to [Problem].
  Result<T> exec(
    void Function(T value) sideEffect, {
    required Problem Function(Object error, StackTrace stackTrace) onException,
  }) {
    if (this case Ok<T>(:final value)) {
      try {
        sideEffect(value);
      } on Object catch (error, stackTrace) {
        return Err<T>(onException(error, stackTrace));
      }
    }

    return this;
  }

  /// Returns the [Ok] value or throws [UnwrapError].
  T unwrap() => switch (this) {
    Ok<T>(:final value) => value,
    Err<T>(:final problem) => throw UnwrapError(
      monad: MonadKind.result,
      expected: 'Ok',
      actual: 'Err',
      payload: problem,
    ),
  };

  /// Returns the [Err] problem or throws [UnwrapError].
  Problem unwrapErr() => switch (this) {
    Ok<T>(:final value) => throw UnwrapError(
      monad: MonadKind.result,
      expected: 'Err',
      actual: 'Ok',
      payload: value,
    ),
    Err<T>(:final problem) => problem,
  };

  T unwrapOr(T fallback) => switch (this) {
    Ok<T>(:final value) => value,
    Err<T>() => fallback,
  };

  T unwrapOrElse(T Function(Problem problem) fallback) => switch (this) {
    Ok<T>(:final value) => value,
    Err<T>(:final problem) => fallback(problem),
  };

  /// Projects the [Ok] channel into an [Option].
  Option<T> ok() => switch (this) {
    Ok<T>(:final value) => Some<T>(value),
    Err<T>() => None<T>(),
  };

  /// Projects the [Err] channel into an [Option].
  Option<Problem> err() => switch (this) {
    Ok<T>() => const None<Problem>(),
    Err<T>(:final problem) => Some<Problem>(problem),
  };

  /// Returns the payload of whichever variant is present.
  Object? native() => switch (this) {
    Ok<T>(:final value) => value,
    Err<T>(:final problem) => problem,
  };

  ResultSerial serial({Object? Function(T value)? encodeOk}) => switch (this) {
    Ok<T>(:final value) => taggedWire('ok', encodeOk?.call(value) ?? value),
    Err<T>(:final problem) => taggedWire('err', problem.toJson()),
  };
}

Problem _decodeProblem(Object? value) {
  if (value is! Map<Object?, Object?>) {
    throw const FormatException('Problem wire value must be an object.');
  }

  final Map<String, Object?> json = value.map<String, Object?>(
    (Object? key, Object? item) =>
        MapEntry<String, Object?>(key.toString(), item),
  );
  _requireProblemString(json, 'type');
  _requireProblemString(json, 'title');
  _requireProblemInt(json, 'status');
  _validateOptionalProblemString(json, 'detail');
  _validateOptionalProblemString(json, 'instance');
  _validateOptionalProblemBool(json, 'recoverable');
  _validateOptionalProblemData(json, 'data');
  return Problem.fromJson(json);
}

void _requireProblemString(Map<String, Object?> json, String key) {
  final Object? value = json[key];
  if (value is! String || value.isEmpty) {
    throw FormatException('Problem.$key must be a non-empty string.');
  }
}

void _requireProblemInt(Map<String, Object?> json, String key) {
  if (json[key] is! int) {
    throw FormatException('Problem.$key must be an integer.');
  }
}

void _validateOptionalProblemString(Map<String, Object?> json, String key) {
  final Object? value = json[key];
  if (value != null && value is! String) {
    throw FormatException('Problem.$key must be a string when present.');
  }
}

void _validateOptionalProblemBool(Map<String, Object?> json, String key) {
  final Object? value = json[key];
  if (value != null && value is! bool) {
    throw FormatException('Problem.$key must be a boolean when present.');
  }
}

void _validateOptionalProblemData(Map<String, Object?> json, String key) {
  final Object? value = json[key];
  if (value != null && value is! Map<Object?, Object?>) {
    throw FormatException('Problem.$key must be an object when present.');
  }
}

final class Ok<T> extends Result<T> {
  const Ok(this.value);

  final T value;

  @override
  String toString() => 'Ok($value)';
}

final class Err<T> extends Result<T> {
  const Err(this.problem);

  final Problem problem;

  @override
  String toString() => 'Err($problem)';
}

/// Async forms of the [Result] combinators for `Future<Result<T>>`.
extension FutureResult<T> on Future<Result<T>> {
  Future<Result<R>> map<R>(FutureOr<R> Function(T value) mapper) async {
    final Result<T> result = await this;
    return switch (result) {
      Ok<T>(:final value) => Ok<R>(await mapper(value)),
      Err<T>(:final problem) => Err<R>(problem),
    };
  }

  Future<Result<T>> mapErr(
    FutureOr<Problem> Function(Problem problem) mapper,
  ) async {
    final Result<T> result = await this;
    return switch (result) {
      Ok<T>(:final value) => Ok<T>(value),
      Err<T>(:final problem) => Err<T>(await mapper(problem)),
    };
  }

  Future<Result<R>> andThen<R>(
    FutureOr<Result<R>> Function(T value) mapper,
  ) async {
    final Result<T> result = await this;
    return switch (result) {
      Ok<T>(:final value) => await mapper(value),
      Err<T>(:final problem) => Err<R>(problem),
    };
  }

  Future<R> match<R>({
    required FutureOr<R> Function(T value) ok,
    required FutureOr<R> Function(Problem problem) err,
  }) async {
    final Result<T> result = await this;
    return switch (result) {
      Ok<T>(:final value) => await ok(value),
      Err<T>(:final problem) => await err(problem),
    };
  }

  Future<T> unwrap() async => (await this).unwrap();

  Future<Problem> unwrapErr() async => (await this).unwrapErr();
}
