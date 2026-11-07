import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:diene_problems/diene_problems.dart';
import 'package:test/test.dart';

const String _fixturesPath = 'test/fixtures/c0';

const ErrorPortal _portal = ErrorPortal(
  scheme: 'https',
  host: 'errors.atomi.cloud',
  landscape: 'raichu',
  platform: 'nitroso',
  service: 'zinc',
  module: 'api',
);

ProblemCatalog _catalog() => ProblemCatalog(portal: _portal)
  ..addType(
    GenericProblems.validationError,
    endpoints: const <CatalogEndpoint>[
      CatalogEndpoint(method: 'POST', path: '/notes'),
      CatalogEndpoint(method: 'PUT', path: '/notes/{id}'),
    ],
  )
  ..addType(
    GenericProblems.entityNotFound,
    endpoints: const <CatalogEndpoint>[
      CatalogEndpoint(method: 'GET', path: '/notes/{id}'),
    ],
  )
  ..addType(
    GenericProblems.conflict,
    endpoints: const <CatalogEndpoint>[
      CatalogEndpoint(method: 'POST', path: '/notes'),
    ],
  )
  ..addType(
    GenericProblems.unauthenticated,
    endpoints: const <CatalogEndpoint>[
      CatalogEndpoint(method: 'GET', path: '/notes'),
    ],
  )
  ..addType(
    GenericProblems.unauthorized,
    endpoints: const <CatalogEndpoint>[
      CatalogEndpoint(method: 'GET', path: '/notes'),
    ],
  )
  ..addType(
    GenericProblems.invalidJson,
    endpoints: const <CatalogEndpoint>[
      CatalogEndpoint(method: 'POST', path: '/notes'),
    ],
  );

Object? _roundTripEnvelope(Map<String, Object?> wire) => Problem.fromJson(
  _decode(jsonEncode(Problem.fromJson(wire).toJson())),
).toJson();

Object? _rebuildTypeUri(Map<String, Object?> wire) {
  final Map<String, Object?> portal = wire['portal']! as Map<String, Object?>;
  return <String, Object?>{
    ...wire,
    'typeUri': problemTypeUri(
      portal: ErrorPortal(
        scheme: portal['scheme']! as String,
        host: portal['host']! as String,
        landscape: portal['landscape']! as String,
        platform: portal['platform']! as String,
        service: portal['service']! as String,
        module: portal['module']! as String,
      ),
      version: wire['version']! as String,
      id: wire['id']! as String,
    ),
  };
}

final Map<String, Object? Function(Map<String, Object?>)> _rebuild =
    <String, Object? Function(Map<String, Object?>)>{
      'envelope.json': _roundTripEnvelope,
      'envelope_no_data.json': _roundTripEnvelope,
      'type_uri.json': _rebuildTypeUri,
      'catalog_entry.json': (_) =>
          _catalog().lookup('validation_error')!.toCrdContent(),
      'problem_cr.json': (_) => _catalog().toProblemResource(version: 'v1'),
    };

void main() {
  final Map<String, Object?> manifest = _decode(
    File('$_fixturesPath/manifest.json').readAsStringSync(),
  );
  final Map<String, Object?> fixtures =
      (manifest['fixtures']! as Map<Object?, Object?>).cast<String, Object?>();

  test('manifest is local, sha256 and pins exactly the checked fixtures', () {
    // Arrange
    final Set<String> checked = _rebuild.keys.toSet();

    // Act
    final Set<String> pinned = fixtures.keys.toSet();

    // Assert
    expect(manifest['authority'], 'local-regression-only');
    expect(manifest['algorithm'], 'sha256');
    expect(pinned, checked);
  });

  group('Problem wire fixtures', () {
    fixtures.forEach((String name, Object? digest) {
      test(name, () {
        // Arrange
        final List<int> bytes = File('$_fixturesPath/$name').readAsBytesSync();
        final Map<String, Object?> wire = _decode(utf8.decode(bytes));

        // Act
        final String actualDigest = sha256.convert(bytes).toString();
        final Object? rebuilt = _rebuild[name]!(wire);

        // Assert
        expect(
          actualDigest,
          digest,
          reason: 'fixture "$name" digest drifted from the manifest',
        );
        expect(rebuilt, wire, reason: '$name no longer matches the code');
      });
    });
  });

  test('a data-less envelope omits data on the wire', () {
    // Arrange
    final Map<String, Object?> wire = _decode(
      File('$_fixturesPath/envelope_no_data.json').readAsStringSync(),
    );

    // Act
    final Map<String, Object?> encoded = Problem.fromJson(wire).toJson();

    // Assert
    expect(encoded.containsKey('data'), isFalse);
  });
}

Map<String, Object?> _decode(String source) =>
    (jsonDecode(source)! as Map<Object?, Object?>).cast<String, Object?>();
