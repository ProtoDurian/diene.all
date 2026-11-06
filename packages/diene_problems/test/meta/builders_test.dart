import 'package:diene_problems/diene_problems.dart';
import 'package:diene_problems/test_helper.dart';
import 'package:test/test.dart';

void main() {
  group('aProblem', () {
    test('builds a valid entity_not_found envelope by default', () {
      // Arrange
      final ProblemRegistry registry = ProblemRegistry(ErrorPortal.localError);

      // Act
      final Problem problem = aProblem();

      // Assert
      expectProblem(
        problem,
        type: registry.typeUriFor(GenericProblems.entityNotFound),
        status: GenericProblems.entityNotFound.status,
        recoverable: GenericProblems.entityNotFound.recoverable,
        data: <String, Object?>{'entityType': 'user', 'id': '42'},
      );
      expect(Problem.fromJson(problem.toJson()), problem);
    });

    test('honours overrides and builds a data-less envelope', () {
      // Arrange
      final ErrorPortal portal = anErrorPortal(service: 'billing');

      // Act
      final Problem problem = aProblem(
        portal: portal,
        id: 'unauthenticated',
        title: 'Unauthenticated',
        status: 401,
        recoverable: true,
        detail: 'sign in',
        instance: '/me',
        data: null,
      );

      // Assert
      expectProblem(
        problem,
        type: problemTypeUri(
          portal: portal,
          version: 'v1',
          id: 'unauthenticated',
        ),
        status: 401,
        recoverable: true,
        detail: 'sign in',
        instance: '/me',
        noData: true,
      );
      expect(problem.toJson().containsKey('data'), isFalse);
    });

    test('refuses an id the one builder rejects', () {
      // Arrange
      const String kebab = 'entity-not-found';

      // Act
      void act() => aProblem(id: kebab);

      // Assert
      expect(act, throwsA(isA<InvalidProblemTypeSegmentError>()));
    });
  });

  group('anErrorPortal', () {
    test('builds a portal the one builder accepts', () {
      // Arrange
      final ErrorPortal portal = anErrorPortal(
        scheme: 'http',
        host: 'localhost:8080',
        landscape: 'pichu',
        platform: 'go',
        module: 'svc',
      );

      // Act
      final String uri = problemTypeUri(portal: portal, version: 'v1', id: 'x');

      // Assert
      expect(uri, 'http://localhost:8080/docs/pichu/go/user/svc/v1/x');
    });
  });

  group('aCatalogEntry', () {
    test('builds an entry whose type URI comes from the one builder', () {
      // Arrange
      final ErrorPortal portal = anErrorPortal();

      // Act
      final CatalogEntry entry = aCatalogEntry(
        portal: portal,
        id: 'conflict',
        title: 'Conflict',
        status: 409,
        recoverable: true,
        dataSchema: GenericProblems.conflict.dataSchema,
        endpoints: const <CatalogEndpoint>[
          CatalogEndpoint(method: 'POST', path: '/user'),
        ],
      );

      // Assert
      expect(
        entry.typeUri,
        ProblemRegistry(portal).typeUriFor(GenericProblems.conflict),
      );
      expect(
        entry.toCrdContent()['schema'],
        GenericProblems.conflict.dataSchema,
      );
      expect(entry.endpoints.single.method, 'POST');
    });

    test('defaults to a data-less entry on the local-error portal', () {
      // Arrange
      const String id = 'unauthorized';

      // Act
      final CatalogEntry entry = aCatalogEntry(id: id);

      // Assert
      expect(entry.typeUri, endsWith('/core/v1/unauthorized'));
      expect(entry.toCrdContent()['schema'], noProblemDataSchema);
    });
  });
}
