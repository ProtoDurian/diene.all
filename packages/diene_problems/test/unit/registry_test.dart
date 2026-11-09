import 'package:diene_problems/diene_problems.dart';
import 'package:test/test.dart';

const ErrorPortal _portal = ErrorPortal(
  scheme: 'https',
  host: 'docs.raichu.cluster.atomi.cloud',
  landscape: 'raichu',
  platform: 'dotnet',
  service: 'user',
  module: 'api',
);

const Map<String, Object?> _entityReference = <String, Object?>{
  'type': 'object',
  'properties': <String, Object?>{
    'entityType': <String, Object?>{'type': 'string'},
    'id': <String, Object?>{'type': 'string'},
  },
  'required': <String>['entityType', 'id'],
  'additionalProperties': false,
};

void main() {
  group('ProblemRegistry', () {
    test('registers, looks up and requires types in order', () {
      // Arrange
      final ProblemRegistry registry = ProblemRegistry(_portal, <ProblemType>[
        GenericProblems.conflict,
      ]);

      // Act
      registry.register(GenericProblems.unauthorized);

      // Assert
      expect(registry.lookup('conflict'), same(GenericProblems.conflict));
      expect(registry.lookup('missing'), isNull);
      expect(registry.require('unauthorized'), GenericProblems.unauthorized);
      expect(registry.entries.map((ProblemType type) => type.id), <String>[
        'conflict',
        'unauthorized',
      ]);
    });

    test('rejects a duplicate id and an unknown required id', () {
      // Arrange
      final ProblemRegistry registry = ProblemRegistry(_portal)
        ..register(GenericProblems.conflict);

      // Act
      void duplicate() => registry.register(GenericProblems.conflict);
      void unknown() => registry.require('missing');

      // Assert
      expect(duplicate, throwsA(isA<DuplicateProblemTypeError>()));
      expect(unknown, throwsA(isA<UnknownProblemTypeError>()));
    });

    test('builds the type URI through the one builder', () {
      // Arrange
      final ProblemRegistry registry = ProblemRegistry(_portal);

      // Act
      final String uri = registry.typeUriFor(GenericProblems.entityNotFound);

      // Assert
      expect(
        uri,
        'https://docs.raichu.cluster.atomi.cloud/docs/raichu/dotnet/user/api/v1/entity_not_found',
      );
    });
  });

  group('GenericProblems', () {
    test('ships the baseline ids, statuses and recoverable flags', () {
      // Arrange
      final ProblemRegistry registry = ProblemRegistry(_portal);

      // Act
      GenericProblems.registerAll(registry);

      // Assert
      expect(
        registry.entries.map(
          (ProblemType type) =>
              '${type.id} ${type.status} ${type.recoverable} ${type.version}',
        ),
        <String>[
          'validation_error 400 true v1',
          'entity_not_found 404 false v1',
          'conflict 409 true v1',
          'unauthenticated 401 true v1',
          'unauthorized 403 false v1',
          'invalid_json 400 true v1',
        ],
      );
    });

    test('gives conflict the same data schema as entity_not_found', () {
      // Arrange
      const ProblemType conflict = GenericProblems.conflict;

      // Act
      final Map<String, Object?>? schema = conflict.dataSchema;

      // Assert
      expect(schema, _entityReference);
      expect(GenericProblems.entityNotFound.dataSchema, _entityReference);
    });

    test('describes validation issues as path, message and optional code', () {
      // Arrange
      const ProblemType validation = GenericProblems.validationError;

      // Act
      final Map<String, Object?> issue =
          ((validation.dataSchema!['properties']!
                      as Map<String, Object?>)['issues']!
                  as Map<String, Object?>)['items']!
              as Map<String, Object?>;

      // Assert
      expect(validation.dataSchema!['required'], <String>['issues']);
      expect(issue['required'], <String>['path', 'message']);
      expect((issue['properties']! as Map<String, Object?>).keys, <String>[
        'path',
        'message',
        'code',
      ]);
    });

    test('gives the data-less generics no data schema', () {
      // Arrange
      const List<ProblemType> dataLess = <ProblemType>[
        GenericProblems.unauthenticated,
        GenericProblems.unauthorized,
        GenericProblems.invalidJson,
      ];

      // Act
      final Iterable<Object?> schemas = dataLess.map(
        (ProblemType type) => type.dataSchema,
      );

      // Assert
      expect(schemas, everyElement(isNull));
      expect(noProblemDataSchema, <String, Object?>{
        'not': <String, Object?>{},
      });
    });
  });
}
