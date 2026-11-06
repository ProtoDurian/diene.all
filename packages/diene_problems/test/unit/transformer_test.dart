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

void main() {
  group('fromObject', () {
    test('returns a Problem unchanged', () {
      // Arrange
      const Problem problem = Problem(type: 't', title: 'T', status: 500);

      // Act
      final Problem folded = fromObject(problem);

      // Assert
      expect(folded, same(problem));
    });

    test('maps a known problemId to the registry type and keeps data', () {
      // Arrange
      final ProblemRegistry registry = ProblemRegistry(_portal)
        ..register(GenericProblems.entityNotFound);
      final Map<String, Object?> error = <String, Object?>{
        'problemId': 'entity_not_found',
        'data': <String, Object?>{'entityType': 'user', 'id': '42'},
      };

      // Act
      final Problem problem = fromObject(
        error,
        options: TransformOptions(registry: registry, portal: _portal),
      );

      // Assert
      expect(problem.status, 404);
      expect(problem.recoverable, isFalse);
      expect(problem.type, registry.typeUriFor(GenericProblems.entityNotFound));
      expect(problem.data, <String, Object?>{'entityType': 'user', 'id': '42'});
    });

    test('uses the default status and no data when the type has neither', () {
      // Arrange
      final ProblemRegistry registry = ProblemRegistry(_portal)
        ..register(const ProblemType(id: 'odd', title: 'Odd', version: 'v1'));

      // Act
      final Problem problem = fromObject(<String, Object?>{
        'problemId': 'odd',
        'data': 'not a map',
      }, options: TransformOptions(registry: registry, defaultStatus: 502));

      // Assert
      expect(problem.status, 502);
      expect(problem.data, isNull);
      expect(problem.toJson().containsKey('data'), isFalse);
    });

    test('falls back to the uncatalogued problem', () {
      // Arrange
      final ProblemRegistry registry = ProblemRegistry(_portal);
      final List<Object?> values = <Object?>[
        StateError('boom'),
        <String, Object?>{'problemId': 'nope'},
        <String, Object?>{'problemId': 7},
        null,
      ];

      // Act
      final List<Problem> problems = values
          .map(
            (Object? value) => fromObject(
              value,
              options: TransformOptions(portal: _portal, registry: registry),
            ),
          )
          .toList();

      // Assert
      for (final Problem problem in problems) {
        expect(problem.type, endsWith('/v1/$uncataloguedProblemId'));
        expect(problem.status, 500);
        expect(problem.data, isNull);
      }
      expect(problems.first.detail, contains('boom'));
      expect(problems.last.detail, isNull);
    });

    test('ignores a problemId when no registry is given', () {
      // Arrange
      final Map<String, Object?> error = <String, Object?>{
        'problemId': 'entity_not_found',
      };

      // Act
      final Problem problem = fromObject(error);

      // Assert
      expect(
        problem.type,
        'https://local.atomi.cloud/docs/local/flutter/app/core/v1/uncatalogued',
      );
    });
  });
}
