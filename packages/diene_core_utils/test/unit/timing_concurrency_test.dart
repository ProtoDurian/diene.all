import 'dart:async';

import 'package:diene_core_utils/diene_core_utils.dart';
import 'package:diene_problems/diene_problems.dart';
import 'package:diene_result/diene_result.dart';
import 'package:test/test.dart';

void main() {
  group('sleep', () {
    test('zero waits successfully', () async {
      // Arrange
      const Duration duration = Duration.zero;

      // Act
      final Result<void> slept = await sleep(duration);

      // Assert
      expect(slept.isOk, isTrue);
    });

    test('a positive duration actually elapses', () async {
      // Arrange
      final Stopwatch clock = Stopwatch()..start();

      // Act
      final Result<void> slept = await sleep(const Duration(milliseconds: 20));
      clock.stop();

      // Assert
      expect(slept.isOk, isTrue);
      expect(clock.elapsedMilliseconds, greaterThanOrEqualTo(15));
    });

    test(
      'a negative duration fails as a value and schedules no timer',
      () async {
        // Arrange
        final Stopwatch clock = Stopwatch()..start();

        // Act
        final Result<void> slept = await sleep(const Duration(seconds: -30));
        clock.stop();

        // Assert
        expect(slept.isErr, isTrue);
        expect(clock.elapsedMilliseconds, lessThan(1000));
        final Problem problem = slept.unwrapErr();
        expect(problem.status, 400);
        expect(problem.data['util'], 'timing');
        expect(problem.data['code'], 'invalid_input');
        expect(problem.data['field'], 'duration');
        expect(problem.type, endsWith('timing_invalid_input'));
      },
    );
  });

  group('mapWithConcurrency', () {
    test('preserves input order regardless of completion order', () async {
      // Arrange
      final List<int> items = <int>[1, 2, 3];

      // Act
      final Result<List<int>> mapped = await mapWithConcurrency<int, int>(
        items,
        3,
        (int value) async {
          await Future<void>.delayed(Duration(milliseconds: 30 - value * 10));
          return Ok<int>(value);
        },
      );

      // Assert
      expect(mapped.unwrap(), <int>[1, 2, 3]);
    });

    test('never exceeds the concurrency bound', () async {
      // Arrange
      int inFlight = 0;
      int peak = 0;
      final List<int> items = List<int>.generate(20, (int i) => i);

      // Act
      final Result<List<int>> mapped = await mapWithConcurrency<int, int>(
        items,
        3,
        (int value) async {
          inFlight += 1;
          peak = inFlight > peak ? inFlight : peak;
          await Future<void>.delayed(const Duration(milliseconds: 2));
          inFlight -= 1;
          return Ok<int>(value * 2);
        },
      );

      // Assert
      expect(mapped.unwrap(), List<int>.generate(20, (int i) => i * 2));
      expect(peak, lessThanOrEqualTo(3));
      expect(
        peak,
        greaterThan(1),
        reason: 'work did not actually run in parallel',
      );
    });

    test(
      'a bound larger than the item count is clamped, not spun up idle',
      () async {
        // Arrange
        int started = 0;

        // Act
        final Result<List<int>> mapped = await mapWithConcurrency<int, int>(
          <int>[1, 2],
          50,
          (int value) async {
            started += 1;
            return Ok<int>(value);
          },
        );

        // Assert
        expect(mapped.unwrap(), <int>[1, 2]);
        expect(started, 2);
      },
    );

    test(
      'an empty input yields an empty list without calling the mapper',
      () async {
        // Arrange
        int called = 0;

        // Act
        final Result<List<int>> mapped = await mapWithConcurrency<int, int>(
          <int>[],
          4,
          (int value) async {
            called += 1;
            return Ok<int>(value);
          },
        );

        // Assert
        expect(mapped.unwrap(), isEmpty);
        expect(called, 0);
      },
    );

    test('the result list is unmodifiable', () async {
      // Arrange
      final Result<List<int>> mapped = await mapWithConcurrency<int, int>(
        <int>[1],
        1,
        (int value) async => Ok<int>(value),
      );

      // Act
      void act() => mapped.unwrap().add(2);

      // Assert
      expect(act, throwsUnsupportedError);
    });

    test('a bound below one fails as a value and runs no mapper', () async {
      // Arrange
      final List<int> bounds = <int>[0, -1];
      final List<int> calls = <int>[];

      // Act
      final List<Result<List<int>>> results = <Result<List<int>>>[];
      for (final int bound in bounds) {
        results.add(
          await mapWithConcurrency<int, int>(<int>[1, 2], bound, (
            int value,
          ) async {
            calls.add(value);
            return Ok<int>(value);
          }),
        );
      }

      // Assert
      expect(calls, isEmpty);
      for (int i = 0; i < bounds.length; i++) {
        expect(results[i].isErr, isTrue, reason: 'bound ${bounds[i]} accepted');
        final Problem problem = results[i].unwrapErr();
        expect(problem.data['util'], 'concurrency');
        expect(problem.data['field'], 'concurrency');
        expect(problem.status, 400);
      }
    });

    test(
      'the first failure short-circuits and stops claiming new work',
      () async {
        // Arrange
        final List<int> attempted = <int>[];
        final List<int> items = List<int>.generate(20, (int i) => i);

        // Act
        final Result<List<int>> mapped = await mapWithConcurrency<int, int>(
          items,
          2,
          (int value) async {
            attempted.add(value);
            await Future<void>.delayed(const Duration(milliseconds: 1));
            if (value == 1) {
              return Err<int>(_failure('item 1 refused'));
            }
            return Ok<int>(value);
          },
        );

        // Assert
        expect(mapped.isErr, isTrue);
        expect(mapped.unwrapErr().title, 'item 1 refused');
        expect(
          attempted.length,
          lessThan(20),
          reason: 'work kept being claimed after the failure',
        );
      },
    );

    test('the LOWEST failing index wins, not the first to complete', () async {
      // Arrange
      final List<int> items = <int>[0, 1, 2, 3];

      // Act
      final Result<List<int>> mapped = await mapWithConcurrency<int, int>(
        items,
        4,
        (int value) async {
          if (value == 3) {
            return Err<int>(_failure('index 3'));
          }
          if (value == 1) {
            await Future<void>.delayed(const Duration(milliseconds: 30));
            return Err<int>(_failure('index 1'));
          }
          return Ok<int>(value);
        },
      );

      // Assert
      expect(mapped.unwrapErr().title, 'index 1');
    });

    test('a single failing item reports its problem unchanged', () async {
      // Arrange
      final Problem original = _failure('only item');

      // Act
      final Result<List<int>> mapped = await mapWithConcurrency<int, int>(
        <int>[1],
        1,
        (int value) async => Err<int>(original),
      );

      // Assert
      expect(mapped.unwrapErr(), same(original));
    });
  });

  group('fuzzyIncludes', () {
    test('matches case-insensitively anywhere in the haystack', () {
      // Arrange
      const String haystack = 'Hello World';
      final List<String> needles = <String>['hello', 'WORLD', 'lo Wo'];

      // Act
      final List<bool> results = needles
          .map((String needle) => fuzzyIncludes(haystack, needle))
          .toList();

      // Assert
      expect(results, <bool>[true, true, true]);
    });

    test('an empty needle is always contained', () {
      // Arrange
      final List<String> haystacks = <String>['anything', ''];

      // Act
      final List<bool> results = haystacks
          .map((String haystack) => fuzzyIncludes(haystack, ''))
          .toList();

      // Assert
      expect(results, <bool>[true, true]);
    });

    test('a missing needle is not contained', () {
      // Arrange
      final List<List<String>> pairs = <List<String>>[
        <String>['Hello', 'xyz'],
        <String>['', 'x'],
      ];

      // Act
      final List<bool> results = pairs
          .map((List<String> pair) => fuzzyIncludes(pair[0], pair[1]))
          .toList();

      // Assert
      expect(results, <bool>[false, false]);
    });
  });
}

Problem _failure(String message) => utilProblem(
  util: UtilName.concurrency,
  code: UtilErrorCode.delegated,
  operation: 'test',
  message: message,
);
