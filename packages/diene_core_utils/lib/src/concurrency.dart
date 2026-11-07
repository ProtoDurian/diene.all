library;

import 'dart:async';

import 'package:diene_problems/diene_problems.dart';
import 'package:diene_result/diene_result.dart';

import 'util_problem.dart';

/// Keeps input order; a failure returns the lowest failing index's problem.
Future<Result<List<R>>> mapWithConcurrency<T, R>(
  Iterable<T> items,
  int concurrency,
  Future<Result<R>> Function(T item) mapper,
) async {
  if (concurrency < 1) {
    return invalidUtilInput<List<R>>(
      util: UtilName.concurrency,
      operation: 'mapWithConcurrency',
      field: 'concurrency',
      message: 'concurrency must be at least 1',
    );
  }

  final List<T> pending = items.toList(growable: false);
  if (pending.isEmpty) {
    return Ok<List<R>>(List<R>.unmodifiable(<R>[]));
  }

  final List<R?> slots = List<R?>.filled(pending.length, null);
  final int workers = concurrency < pending.length
      ? concurrency
      : pending.length;
  int next = 0;
  int? failedIndex;
  Problem? failure;
  bool stopped = false;

  Future<void> work() async {
    while (!stopped && next < pending.length) {
      final int index = next;
      next += 1;
      final Result<R> outcome = await mapper(pending[index]);
      switch (outcome) {
        case Ok<R>(value: final R value):
          slots[index] = value;
        case Err<R>(problem: final Problem problem):
          if (failedIndex == null || index < failedIndex!) {
            failedIndex = index;
            failure = problem;
          }
          stopped = true;
      }
    }
  }

  await Future.wait<void>(<Future<void>>[
    for (int worker = 0; worker < workers; worker += 1) work(),
  ]);

  final Problem? observed = failure;
  if (observed != null) {
    return Err<List<R>>(observed);
  }
  return Ok<List<R>>(List<R>.unmodifiable(slots.cast<R>()));
}
