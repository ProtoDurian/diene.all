import 'package:diene_problems/diene_problems.dart';
import 'package:test/test.dart';

ErrorPortal _portal({
  String scheme = 'https',
  String host = 'docs.raichu.cluster.atomi.cloud',
  String landscape = 'raichu',
  String platform = 'dotnet',
  String service = 'user',
  String module = 'api',
}) => ErrorPortal(
  scheme: scheme,
  host: host,
  landscape: landscape,
  platform: platform,
  service: service,
  module: module,
);

void _expectRejected(
  String segment, {
  ErrorPortal? portal,
  String version = 'v1',
  String id = 'entity_not_found',
}) {
  expect(
    () => problemTypeUri(portal: portal ?? _portal(), version: version, id: id),
    throwsA(
      isA<InvalidProblemTypeSegmentError>().having(
        (InvalidProblemTypeSegmentError error) => error.name,
        'name',
        segment,
      ),
    ),
  );
}

void main() {
  group('problemTypeUri', () {
    test('orders every segment landscape to id', () {
      // Arrange
      final ErrorPortal portal = _portal(
        landscape: 'pichu',
        platform: 'go',
        service: 'billing',
        module: 'svc',
      );

      // Act
      final String uri = problemTypeUri(
        portal: portal,
        version: 'v3',
        id: 'payment_declined',
      );

      // Assert
      expect(
        uri,
        'https://docs.raichu.cluster.atomi.cloud/docs/pichu/go/billing/svc/v3/payment_declined',
      );
    });

    test('accepts http and a host:port authority', () {
      // Arrange
      final ErrorPortal portal = _portal(
        scheme: 'http',
        host: 'localhost:8080',
      );

      // Act
      final String uri = problemTypeUri(portal: portal, version: 'v2', id: 'x');

      // Assert
      expect(uri, 'http://localhost:8080/docs/raichu/dotnet/user/api/v2/x');
    });

    test('builds the local-error fallback portal', () {
      // Arrange
      const ErrorPortal portal = ErrorPortal.localError;

      // Act
      final String uri = problemTypeUri(
        portal: portal,
        version: 'v1',
        id: 'local_error',
      );

      // Assert
      expect(
        uri,
        'https://local.atomi.cloud/docs/local/flutter/app/core/v1/local_error',
      );
    });

    test('rejects a scheme other than http or https', () {
      // Arrange
      final ErrorPortal portal = _portal(scheme: 'ftp');

      // Act
      void act() => _expectRejected('scheme', portal: portal);

      // Assert
      act();
    });

    test('rejects a host that is not a bare canonical authority', () {
      // Arrange
      const List<String> hosts = <String>[
        '',
        ' docs.atomi.cloud',
        'docs.atomi.cloud/docs',
        r'docs.atomi.cloud\docs',
        'user@docs.atomi.cloud',
        'docs.atomi.cloud?a=b',
        'docs.atomi.cloud#frag',
        'DOCS.Atomi.Cloud',
      ];

      // Act
      void act(String host) =>
          _expectRejected('host', portal: _portal(host: host));

      // Assert
      hosts.forEach(act);
    });

    test('rejects an invalid landscape, platform, service or module', () {
      // Arrange
      final Map<String, ErrorPortal> portals = <String, ErrorPortal>{
        'landscape': _portal(landscape: ''),
        'platform': _portal(platform: 'a/b'),
        'service': _portal(service: '-svc'),
        'module': _portal(module: 'm o'),
      };

      // Act
      void act(String segment, ErrorPortal portal) =>
          _expectRejected(segment, portal: portal);

      // Assert
      portals.forEach(act);
    });

    test('rejects a version outside v1, v2, …', () {
      // Arrange
      const List<String> versions = <String>['', '1', 'V1', 'v', 'v0', 'v1.2'];

      // Act
      void act(String version) => _expectRejected('version', version: version);

      // Assert
      versions.forEach(act);
    });

    test('rejects a wire id that is not snake_case or is too long', () {
      // Arrange
      final List<String> ids = <String>[
        'entity-not-found',
        'EntityNotFound',
        '1entity',
        '_entity',
        'has/slash',
        'a${'b' * 63}',
      ];

      // Act
      void act(String id) => _expectRejected('id', id: id);

      // Assert
      ids.forEach(act);
      expect(problemWireIdPattern.hasMatch('a${'b' * 62}'), isTrue);
    });
  });
}
