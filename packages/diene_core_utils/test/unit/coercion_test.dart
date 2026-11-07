import 'package:diene_core_utils/diene_core_utils.dart';
import 'package:diene_problems/diene_problems.dart';
import 'package:diene_result/diene_result.dart';
import 'package:test/test.dart';

void main() {
  group('coerceEnvironmentScalar', () {
    test('a blank value is UNSET', () {
      // Arrange
      const String raw = '';

      // Act
      final Object? coerced = coerceEnvironmentScalar(raw);

      // Assert
      expect(coerced, isNull);
    });

    test('booleans coerce in any case', () {
      // Arrange
      final List<String> yes = <String>['true', 'TRUE', 'True', 'tRuE'];
      final List<String> no = <String>['false', 'FALSE', 'False'];

      // Act
      final List<Object?> yesResults = yes
          .map(coerceEnvironmentScalar)
          .toList();
      final List<Object?> noResults = no.map(coerceEnvironmentScalar).toList();

      // Assert
      for (int i = 0; i < yes.length; i++) {
        expect(yesResults[i], true, reason: yes[i]);
      }
      for (int i = 0; i < no.length; i++) {
        expect(noResults[i], false, reason: no[i]);
      }
    });

    test('safe integers coerce to int, including signs and zero', () {
      // Arrange
      final List<String> raws = <String>['0', '42', '-7', '+7'];

      // Act
      final List<Object?> coerced = raws.map(coerceEnvironmentScalar).toList();

      // Assert
      expect(coerced, <Object?>[0, 42, -7, 7]);
    });

    test('an integer beyond the IEEE-754 safe range stays a String', () {
      // Arrange
      final List<String> raws = <String>[
        '9007199254740991',
        '9007199254740992',
        '-9007199254740992',
      ];

      // Act
      final List<Object?> coerced = raws.map(coerceEnvironmentScalar).toList();

      // Assert
      expect(coerced, <Object?>[
        9007199254740991,
        '9007199254740992',
        '-9007199254740992',
      ]);
    });

    test('decimal and exponent forms coerce to double', () {
      // Arrange
      final List<String> raws = <String>['1.5', '-0.25', '1e3', '1.5e2'];

      // Act
      final List<Object?> coerced = raws.map(coerceEnvironmentScalar).toList();

      // Assert
      expect(coerced, <Object?>[1.5, -0.25, 1000.0, 150.0]);
    });

    test('leading zeros, bare dots, and words stay Strings', () {
      // Arrange
      final List<String> raws = <String>[
        '007',
        '1.',
        '.5',
        'yes',
        'null',
        '1,5',
        '0x10',
        '  42  ',
      ];

      // Act
      final List<Object?> coerced = raws.map(coerceEnvironmentScalar).toList();

      // Assert
      for (int i = 0; i < raws.length; i++) {
        expect(coerced[i], raws[i], reason: raws[i]);
      }
    });
  });

  group('environmentToNestedMap', () {
    test('builds a nested object from __-separated paths', () {
      // Arrange
      final Map<String, String> environment = <String, String>{
        'ACME_APP__NAME': 'service',
        'ACME_APP__LIMITS__RETRIES': '3',
      };

      // Act
      final Result<JsonObject> nested = environmentToNestedMap(
        environment,
        prefix: 'ACME_',
      );

      // Assert
      expect(nested.unwrap(), <String, Object?>{
        'app': <String, Object?>{
          'name': 'service',
          'limits': <String, Object?>{'retries': 3},
        },
      });
    });

    test('ignores keys outside the prefix', () {
      // Arrange
      final Map<String, String> environment = <String, String>{
        'ACME_A': '1',
        'OTHER_B': '2',
        'PATH': '/usr/bin',
      };

      // Act
      final Result<JsonObject> nested = environmentToNestedMap(
        environment,
        prefix: 'ACME_',
      );

      // Assert
      expect(nested.unwrap(), <String, Object?>{'a': 1});
    });

    test('lowercases path components so any YAML spelling merges', () {
      // Arrange
      final Map<String, String> environment = <String, String>{
        'ACME_APP__DISPLAY_NAME': 'x',
      };

      // Act
      final Result<JsonObject> nested = environmentToNestedMap(
        environment,
        prefix: 'ACME_',
      );

      // Assert
      expect(nested.unwrap(), <String, Object?>{
        'app': <String, Object?>{'display_name': 'x'},
      });
    });

    test('indexed keys build a list in index order, not key order', () {
      // Arrange
      final Map<String, String> environment = <String, String>{
        'ACME_TAGS__1': 'second',
        'ACME_TAGS__0': 'first',
        'ACME_TAGS__2': 'third',
      };

      // Act
      final Result<JsonObject> nested = environmentToNestedMap(
        environment,
        prefix: 'ACME_',
      );

      // Assert
      expect(nested.unwrap(), <String, Object?>{
        'tags': <Object?>['first', 'second', 'third'],
      });
    });

    test('a list of objects materialises at depth', () {
      // Arrange
      final Map<String, String> environment = <String, String>{
        'ACME_BACKENDS__0__NAME': 'alpha',
        'ACME_BACKENDS__1__NAME': 'beta',
      };

      // Act
      final Result<JsonObject> nested = environmentToNestedMap(
        environment,
        prefix: 'ACME_',
      );

      // Assert
      expect(nested.unwrap(), <String, Object?>{
        'backends': <Object?>[
          <String, Object?>{'name': 'alpha'},
          <String, Object?>{'name': 'beta'},
        ],
      });
    });

    test('blank values are omitted entirely, never written as null', () {
      // Arrange
      final Map<String, String> environment = <String, String>{
        'ACME_A': '',
        'ACME_B': '1',
      };

      // Act
      final Result<JsonObject> nested = environmentToNestedMap(
        environment,
        prefix: 'ACME_',
      );

      // Assert
      expect(nested.unwrap(), <String, Object?>{'b': 1});
      expect(nested.unwrap().containsKey('a'), isFalse);
    });

    test('an empty environment yields an empty object', () {
      // Arrange
      final Map<String, String> environment = <String, String>{};

      // Act
      final Result<JsonObject> nested = environmentToNestedMap(
        environment,
        prefix: 'ACME_',
      );

      // Assert
      expect(nested.unwrap(), isEmpty);
    });

    test('an empty prefix takes every key', () {
      // Arrange
      final Map<String, String> environment = <String, String>{'A': '1'};

      // Act
      final Result<JsonObject> nested = environmentToNestedMap(
        environment,
        prefix: '',
      );

      // Assert
      expect(nested.unwrap(), <String, Object?>{'a': 1});
    });

    test('a key that is only the prefix is rejected', () {
      // Arrange
      final Map<String, String> environment = <String, String>{'ACME_': 'x'};

      // Act
      final Result<JsonObject> nested = environmentToNestedMap(
        environment,
        prefix: 'ACME_',
      );

      // Assert
      _expectCoercionProblem(nested, 'invalid_input', 400);
      expect(nested.unwrapErr().data['field'], 'ACME_');
    });

    test('an empty path component is rejected', () {
      // Arrange
      final Map<String, String> environment = <String, String>{
        'ACME_APP____NAME': 'x',
      };

      // Act
      final Result<JsonObject> nested = environmentToNestedMap(
        environment,
        prefix: 'ACME_',
      );

      // Assert
      _expectCoercionProblem(nested, 'invalid_input', 400);
    });

    test('two keys normalising onto the same path conflict', () {
      // Arrange
      final Map<String, String> environment = <String, String>{
        'ACME_APP__NAME': 'a',
        'ACME_app__name': 'b',
      };

      // Act
      final Result<JsonObject> nested = environmentToNestedMap(
        environment,
        prefix: 'ACME_',
      );

      // Assert
      _expectCoercionProblem(nested, 'conflict', 409);
      expect(nested.unwrapErr().data['path'], 'name');
    });

    test('a key treating a scalar path as a parent conflicts', () {
      // Arrange
      final Map<String, String> environment = <String, String>{
        'ACME_APP': 'scalar',
        'ACME_APP__NAME': 'child',
      };

      // Act
      final Result<JsonObject> nested = environmentToNestedMap(
        environment,
        prefix: 'ACME_',
      );

      // Assert
      _expectCoercionProblem(nested, 'conflict', 409);
      expect(nested.unwrapErr().data['path'], 'app');
    });

    test('mixing indexed and named children is rejected', () {
      // Arrange
      final Map<String, String> environment = <String, String>{
        'ACME_TAGS__0': 'a',
        'ACME_TAGS__NAME': 'b',
      };

      // Act
      final Result<JsonObject> nested = environmentToNestedMap(
        environment,
        prefix: 'ACME_',
      );

      // Assert
      _expectCoercionProblem(nested, 'invalid_input', 400);
      expect(nested.unwrapErr().data['field'], contains('tags'));
    });

    test('a list not starting at zero is rejected', () {
      // Arrange
      final Map<String, String> environment = <String, String>{
        'ACME_TAGS__1': 'a',
      };

      // Act
      final Result<JsonObject> nested = environmentToNestedMap(
        environment,
        prefix: 'ACME_',
      );

      // Assert
      _expectCoercionProblem(nested, 'invalid_input', 400);
      expect(nested.unwrapErr().title, contains('sparse'));
    });

    test('a sparse list is rejected', () {
      // Arrange
      final Map<String, String> environment = <String, String>{
        'ACME_TAGS__0': 'a',
        'ACME_TAGS__2': 'c',
      };

      // Act
      final Result<JsonObject> nested = environmentToNestedMap(
        environment,
        prefix: 'ACME_',
      );

      // Assert
      _expectCoercionProblem(nested, 'invalid_input', 400);
      expect(nested.unwrapErr().title, contains('expected 1'));
    });

    test('a nested failure propagates out of a list element', () {
      // Arrange
      final Map<String, String> environment = <String, String>{
        'ACME_BACKENDS__0__PORTS__0': '1',
        'ACME_BACKENDS__0__PORTS__NAME': 'x',
      };

      // Act
      final Result<JsonObject> nested = environmentToNestedMap(
        environment,
        prefix: 'ACME_',
      );

      // Assert
      _expectCoercionProblem(nested, 'invalid_input', 400);
      expect(nested.unwrapErr().data['field'], contains('ports'));
    });

    test('a nested failure propagates out of a named child', () {
      // Arrange
      final Map<String, String> environment = <String, String>{
        'ACME_APP__TAGS__0': 'a',
        'ACME_APP__TAGS__NAME': 'x',
      };

      // Act
      final Result<JsonObject> nested = environmentToNestedMap(
        environment,
        prefix: 'ACME_',
      );

      // Assert
      _expectCoercionProblem(nested, 'invalid_input', 400);
    });
  });

  group('environmentPathSeparator', () {
    test('is the double underscore', () {
      // Arrange
      // Act
      final String separator = environmentPathSeparator;

      // Assert
      expect(separator, '__');
    });
  });
}

void _expectCoercionProblem(
  Result<Object?> result,
  String expectedCode,
  int expectedStatus,
) {
  expect(result.isErr, isTrue, reason: 'expected a failure, got $result');
  final Problem problem = result.unwrapErr();
  expect(problem.data['util'], 'coercion');
  expect(problem.data['code'], expectedCode);
  expect(problem.data['operation'], 'environmentToNestedMap');
  expect(problem.status, expectedStatus);
  expect(problem.recoverable, isFalse);
  expect(problem.type, endsWith('coercion_$expectedCode'));
}
