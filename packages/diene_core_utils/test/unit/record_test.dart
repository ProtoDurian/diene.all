import 'dart:convert';

import 'package:diene_core_utils/diene_core_utils.dart';
import 'package:diene_problems/diene_problems.dart';
import 'package:diene_result/diene_result.dart';
import 'package:test/test.dart';

void main() {
  group('isJsonObject', () {
    test('accepts string-keyed maps only', () {
      // Arrange
      final List<Object?> candidates = <Object?>[
        <String, Object?>{},
        <String, Object?>{'a': 1},
      ];

      // Act
      final List<bool> results = candidates.map(isJsonObject).toList();

      // Assert
      expect(results, <bool>[true, true]);
    });

    test('rejects lists, scalars, null, and non-string-keyed maps', () {
      // Arrange
      final List<Object?> candidates = <Object?>[
        <Object?>[],
        null,
        1,
        'x',
        <int, Object?>{1: 'a'},
      ];

      // Act
      final List<bool> results = candidates.map(isJsonObject).toList();

      // Assert
      expect(results, <bool>[false, false, false, false, false]);
    });
  });

  group('stableConfig', () {
    test('sorts object keys at every depth', () {
      // Arrange
      final JsonObject config = <String, Object?>{
        'z': 1,
        'a': <String, Object?>{'y': 2, 'b': 3},
      };

      // Act
      final Result<Object?> projected = stableConfig(config);

      // Assert
      expect(jsonEncode(projected.unwrap()), '{"a":{"b":3,"y":2},"z":1}');
    });

    test('preserves list element order', () {
      // Arrange
      final List<Object?> config = <Object?>[3, 1, 2];

      // Act
      final Result<Object?> projected = stableConfig(config);

      // Assert
      expect(projected.unwrap(), <Object?>[3, 1, 2]);
    });

    test('two structurally equal configs project to identical JSON', () {
      // Arrange
      final JsonObject leftConfig = <String, Object?>{
        'b': 1,
        'a': <Object?>[
          <String, Object?>{'d': 4, 'c': 3},
        ],
      };
      final JsonObject rightConfig = <String, Object?>{
        'a': <Object?>[
          <String, Object?>{'c': 3, 'd': 4},
        ],
        'b': 1,
      };

      // Act
      final Object? left = stableConfig(leftConfig).unwrap();
      final Object? right = stableConfig(rightConfig).unwrap();

      // Assert
      expect(jsonEncode(left), jsonEncode(right));
    });

    test('scalars and null pass through', () {
      // Arrange
      final List<Object?> inputs = <Object?>[null, 7, 'x', true];

      // Act
      final List<Object?> projected = inputs
          .map((Object? input) => stableConfig(input).unwrap())
          .toList();

      // Assert
      expect(projected, <Object?>[null, 7, 'x', true]);
    });

    test(
      'a value shared across sibling branches is fine (a DAG is not a cycle)',
      () {
        // Arrange
        final JsonObject shared = <String, Object?>{'s': 1};
        final JsonObject config = <String, Object?>{
          'left': shared,
          'right': shared,
        };

        // Act
        final Result<Object?> projected = stableConfig(config);

        // Assert
        expect(projected.isOk, isTrue);
        expect(
          jsonEncode(projected.unwrap()),
          '{"left":{"s":1},"right":{"s":1}}',
        );
      },
    );

    test('a self-referential map is reported, not recursed forever', () {
      // Arrange
      final JsonObject cyclic = <String, Object?>{'name': 'root'};
      cyclic['self'] = cyclic;

      // Act
      final Result<Object?> projected = stableConfig(cyclic);

      // Assert
      expect(projected.isErr, isTrue);
      final Problem problem = projected.unwrapErr();
      expect(problem.status, 422);
      expect(problem.data['util'], 'record');
      expect(problem.data['code'], 'unprojectable');
      expect(problem.data['path'], '<root>.self');
      expect(problem.type, endsWith('record_unprojectable'));
    });

    test('a cycle through a list is also reported', () {
      // Arrange
      final List<Object?> cyclic = <Object?>[1];
      cyclic.add(cyclic);

      // Act
      final Result<Object?> projected = stableConfig(cyclic);

      // Assert
      expect(projected.isErr, isTrue);
      expect(projected.unwrapErr().data['path'], '<root>[1]');
    });

    test('a deeper cycle reports the path where it was found', () {
      // Arrange
      final JsonObject inner = <String, Object?>{};
      final JsonObject outer = <String, Object?>{
        'a': <String, Object?>{'b': inner},
      };
      inner['back'] = outer;

      // Act
      final Result<Object?> projected = stableConfig(outer);

      // Assert
      expect(projected.unwrapErr().data['path'], '<root>.a.b.back');
    });
  });

  group('stableConfigObject', () {
    test('keeps the JsonObject type for a merged configuration', () {
      // Arrange
      final JsonObject merged = deepMergeAll(<JsonObject>[
        <String, Object?>{'b': 1},
        <String, Object?>{'a': 2},
      ]);

      // Act
      final Result<JsonObject> projected = stableConfigObject(merged);

      // Assert
      expect(projected.unwrap(), isA<JsonObject>());
      expect(projected.unwrap().keys, <String>['a', 'b']);
    });

    test('propagates the unprojectable failure', () {
      // Arrange
      final JsonObject cyclic = <String, Object?>{};
      cyclic['self'] = cyclic;

      // Act
      final Result<JsonObject> projected = stableConfigObject(cyclic);

      // Assert
      expect(projected.isErr, isTrue);
    });
  });
}
