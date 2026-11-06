import 'package:diene_problems/diene_problems.dart';
import 'package:test/test.dart';

const ErrorPortal _portal = ErrorPortal(
  scheme: 'https',
  host: 'errors.atomi.cloud',
  landscape: 'raichu',
  platform: 'nitroso',
  service: 'zinc',
  module: 'api',
);

const String _base = 'https://errors.atomi.cloud/docs/raichu/nitroso/zinc/api';

ErrorPortal _portalWith({
  String scheme = 'https',
  String platform = 'nitroso',
  String service = 'zinc',
}) => ErrorPortal(
  scheme: scheme,
  host: 'errors.atomi.cloud',
  landscape: 'raichu',
  platform: platform,
  service: service,
  module: 'api',
);

void main() {
  group('CatalogEntry', () {
    test('renders a CR entry with the data schema under schema', () {
      // Arrange
      const CatalogEntry entry = CatalogEntry(
        id: 'note_locked',
        typeUri: '$_base/v1/note_locked',
        title: 'Note locked',
        status: 423,
        recoverable: true,
        dataSchema: <String, Object?>{'type': 'object'},
        endpoints: <CatalogEndpoint>[
          CatalogEndpoint(method: 'PUT', path: '/notes/{id}'),
        ],
      );

      // Act
      final Map<String, Object?> crd = entry.toCrdContent();

      // Assert
      expect(crd, <String, Object?>{
        'id': 'note_locked',
        'type': '$_base/v1/note_locked',
        'title': 'Note locked',
        'status': 423,
        'recoverable': true,
        'schema': <String, Object?>{'type': 'object'},
        'endpoints': <Object?>[
          <String, Object?>{'method': 'PUT', 'path': '/notes/{id}'},
        ],
      });
    });

    test('publishes not-anything as the schema of a data-less problem', () {
      // Arrange
      const CatalogEntry entry = CatalogEntry(
        id: 'unauthorized',
        typeUri: '$_base/v1/unauthorized',
        title: 'Unauthorized',
        status: 403,
        recoverable: false,
      );

      // Act
      final Map<String, Object?> crd = entry.toCrdContent();

      // Assert
      expect(crd['schema'], <String, Object?>{'not': <String, Object?>{}});
      expect(crd['endpoints'], isEmpty);
    });
  });

  group('ProblemCatalog', () {
    test('adds types through the one builder and keeps insertion order', () {
      // Arrange
      final ProblemCatalog catalog = ProblemCatalog(portal: _portal);

      // Act
      catalog
        ..addType(GenericProblems.validationError)
        ..addType(
          const ProblemType(id: 'no_status', title: 'No status', version: 'v1'),
        );

      // Assert
      expect(
        catalog.lookup('validation_error')?.typeUri,
        '$_base/v1/validation_error',
      );
      expect(catalog.lookup('no_status')?.status, 500);
      expect(catalog.lookup('missing'), isNull);
      expect(
        catalog.toCrdContent().map((Map<String, Object?> e) => e['id']),
        <String>['validation_error', 'no_status'],
      );
    });

    test('seeds from entries and replaces an entry with the same id', () {
      // Arrange
      final ProblemCatalog catalog = ProblemCatalog(
        portal: _portal,
        entries: <CatalogEntry>[
          const CatalogEntry(
            id: 'x',
            typeUri: '$_base/v1/x',
            title: 'X',
            status: 400,
            recoverable: false,
          ),
        ],
      );

      // Act
      catalog.add(
        const CatalogEntry(
          id: 'x',
          typeUri: '$_base/v1/x',
          title: 'X2',
          status: 422,
          recoverable: true,
        ),
      );

      // Assert
      expect(catalog.entries.single.title, 'X2');
    });

    test('emits one Problem CR per row, named with dots', () {
      // Arrange
      final ProblemCatalog catalog = ProblemCatalog(portal: _portal)
        ..addGenerics()
        ..addType(
          GenericProblems.conflict,
          endpoints: const <CatalogEndpoint>[
            CatalogEndpoint(method: 'POST', path: '/notes'),
          ],
        );

      // Act
      final Map<String, Object?> resource = catalog.toProblemResource(
        version: 'v1',
      );

      // Assert
      expect(resource['apiVersion'], 'atomi.cloud/v1alpha1');
      expect(resource['kind'], 'Problem');
      expect(resource['metadata'], <String, Object?>{
        'name': 'zinc.api.raichu.v1',
        'namespace': 'nitroso',
      });
      final Map<String, Object?> spec =
          resource['spec']! as Map<String, Object?>;
      expect(spec['platform'], 'nitroso');
      expect(spec['service'], 'zinc');
      expect(spec['module'], 'api');
      expect(spec['landscape'], 'raichu');
      expect(spec['version'], 'v1');
      final List<Object?> problems = spec['problems']! as List<Object?>;
      expect(
        problems.map((Object? p) => (p! as Map<String, Object?>)['id']),
        <String>[
          'conflict',
          'entity_not_found',
          'invalid_json',
          'unauthenticated',
          'unauthorized',
          'validation_error',
        ],
      );
      expect((problems.first! as Map<String, Object?>)['endpoints'], <Object?>[
        <String, Object?>{'method': 'POST', 'path': '/notes'},
      ]);
    });

    test('refuses a row that cannot name a Problem CR', () {
      // Arrange
      final Map<String, ProblemCatalog> catalogs = <String, ProblemCatalog>{
        'http portal': ProblemCatalog(portal: _portalWith(scheme: 'http')),
        'uppercase platform': ProblemCatalog(
          portal: _portalWith(platform: 'Nitroso'),
        ),
        'dotted service': ProblemCatalog(portal: _portalWith(service: 'a.b')),
      };

      // Act
      void act(String reason, ProblemCatalog catalog) => expect(
        () => catalog.toProblemResource(version: 'v1'),
        throwsA(isA<ProblemResourceError>()),
        reason: reason,
      );

      // Assert
      catalogs.forEach(act);
      expect(
        () => ProblemCatalog(portal: _portal).toProblemResource(version: 'v0'),
        throwsA(isA<ProblemResourceError>()),
      );
    });

    test('refuses builder inputs a Problem CR cannot carry', () {
      // Arrange
      final ProblemCatalog ftp = ProblemCatalog(
        portal: _portalWith(scheme: 'ftp'),
      );
      final ProblemCatalog https = ProblemCatalog(portal: _portal);

      // Act
      void act(ProblemCatalog catalog, String version) => expect(
        () => catalog.toProblemResource(version: version),
        throwsA(isA<ProblemResourceError>()),
        reason: '${catalog.portal.scheme} $version',
      );

      // Assert
      act(ftp, 'v1');
      act(https, 'v01');
      act(https, 'v${'1' * 300}');
    });

    test('refuses a resource name longer than 253 characters', () {
      // Arrange
      final String label = 'a' * 63;
      final ProblemCatalog catalog = ProblemCatalog(
        portal: ErrorPortal(
          scheme: 'https',
          host: 'errors.atomi.cloud',
          landscape: label,
          platform: 'nitroso',
          service: label,
          module: label,
        ),
      );

      // Act
      void act() => catalog.toProblemResource(version: 'v${'1' * 62}');

      // Assert
      expect(
        act,
        throwsA(
          isA<ProblemResourceError>().having(
            (ProblemResourceError error) => error.message,
            'message',
            contains('DNS-1123 subdomain'),
          ),
        ),
      );
    });

    test('reports a direct entry the builder rejects as a CR error', () {
      // Arrange
      final ProblemCatalog catalog = ProblemCatalog(
        portal: _portal,
        entries: <CatalogEntry>[
          const CatalogEntry(
            id: 'Bad',
            typeUri: '$_base/v1/Bad',
            title: 'Bad',
            status: 400,
            recoverable: false,
          ),
        ],
      );

      // Act
      void act() => catalog.toProblemResource(version: 'v1');

      // Assert
      expect(
        act,
        throwsA(
          isA<ProblemResourceError>().having(
            (ProblemResourceError error) => error.message,
            'message',
            contains('problem Bad'),
          ),
        ),
      );
    });

    test('refuses an entry built for another row', () {
      // Arrange
      final ProblemCatalog catalog = ProblemCatalog(portal: _portal)
        ..addType(
          const ProblemType(
            id: 'gone',
            title: 'Gone',
            version: 'v2',
            status: 410,
          ),
        );

      // Act
      void act() => catalog.toProblemResource(version: 'v1');

      // Assert
      expect(
        act,
        throwsA(
          isA<ProblemResourceError>().having(
            (ProblemResourceError error) => error.message,
            'message',
            contains('/v2/gone'),
          ),
        ),
      );
    });

    test('refuses an invalid or repeated endpoint', () {
      // Arrange
      final List<List<CatalogEndpoint>> endpointSets = <List<CatalogEndpoint>>[
        <CatalogEndpoint>[const CatalogEndpoint(method: 'get', path: '/notes')],
        <CatalogEndpoint>[const CatalogEndpoint(method: 'GET', path: 'notes')],
        <CatalogEndpoint>[
          const CatalogEndpoint(method: 'GET', path: '/notes'),
          const CatalogEndpoint(method: 'GET', path: '/notes'),
        ],
      ];

      // Act
      void act(List<CatalogEndpoint> endpoints) => expect(
        () =>
            (ProblemCatalog(portal: _portal)
                  ..addType(GenericProblems.conflict, endpoints: endpoints))
                .toProblemResource(version: 'v1'),
        throwsA(isA<ProblemResourceError>()),
      );

      // Assert
      endpointSets.forEach(act);
    });
  });
}
