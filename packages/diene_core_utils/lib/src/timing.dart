library;

import 'dart:async';

import 'package:diene_result/diene_result.dart';

import 'util_problem.dart';

/// Waits [duration]; a negative duration is an `invalid_input` failure.
Future<Result<void>> sleep(Duration duration) async {
  if (duration.isNegative) {
    return invalidUtilInput<void>(
      util: UtilName.timing,
      operation: 'sleep',
      field: 'duration',
      message: 'duration must not be negative',
    );
  }
  await Future<void>.delayed(duration);
  return const Ok<void>(null);
}
