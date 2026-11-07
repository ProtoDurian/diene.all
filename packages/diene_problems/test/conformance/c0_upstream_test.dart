import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:diene_problems/diene_problems.dart';
import 'package:test/test.dart';

const String _upstreamPath = 'test/fixtures/c0/upstream';

Map<String, Object?> _object(Object? value) =>
    (value! as Map<Object?, Object?>).cast<String, Object?>();

List<Map<String, Object?>> _objects(Object? value) =>
    (value! as List<Object?>).map(_object).toList();

Object? _sortKeys(Object? value) {
  if (value is Map<Object?, Object?>) {
    final List<String> keys = value.keys.cast<String>().toList()..sort();
    return <String, Object?>{
      for (final String key in keys) key: _sortKeys(value[key]),
    };
  }
  if (value is List<Object?>) {
    return value.map(_sortKeys).toList();
  }
  return value;
}

String _canonical(Object? value) => '${jsonEncode(_sortKeys(value))}\n';

String _snakeId(String id) => id.replaceAll('-', '_');

String _snakeLastSegment(String uri) {
  final int slash = uri.lastIndexOf('/') + 1;
  return '${uri.substring(0, slash)}${_snakeId(uri.substring(slash))}';
}

void _checkEnvelopes(Map<String, Object?> vector) {
  const Set<String> members = <String>{
    'type',
    'title',
    'status',
    'detail',
    'instance',
    'recoverable',
    'data',
  };
  for (final Map<String, Object?> envelope in _objects(vector['valid'])) {
    expect(members.containsAll(envelope.keys), isTrue);
    expect(
      _canonical(Problem.fromJson(envelope).toJson()),
      _canonical(envelope),
    );
  }
}

void _checkTypeUri(Map<String, Object?> vector) {
  for (final Map<String, Object?> sample in _objects(vector['valid'])) {
    final Map<String, Object?> s = _object(sample['segments']);
    final ErrorPortal portal = ErrorPortal(
      scheme: s['scheme']! as String,
      host: s['host']! as String,
      landscape: s['landscape']! as String,
      platform: s['platform']! as String,
      service: s['service']! as String,
      module: s['module']! as String,
    );
    final String version = s['version']! as String;
    final String id = s['id']! as String;
    expect(
      problemTypeUri(portal: portal, version: version, id: _snakeId(id)),
      _snakeLastSegment(sample['expectedTypeUri']! as String),
    );
    expect(
      () => problemTypeUri(portal: portal, version: version, id: id),
      throwsA(isA<InvalidProblemTypeSegmentError>()),
    );
  }
}

void _checkCatalogEntry(Map<String, Object?> vector) {
  final List<String> shape = (vector['shape']! as List<Object?>)
      .map((Object? key) => key == 'data' ? 'schema' : key! as String)
      .toList();
  for (final Map<String, Object?> sample in _objects(vector['samples'])) {
    final String type = _snakeLastSegment(sample['type']! as String);
    final Uri uri = Uri.parse(type);
    final List<String> path = uri.pathSegments;
    final List<CatalogEndpoint> endpoints = _objects(sample['endpoints'])
        .map(
          (Map<String, Object?> e) => CatalogEndpoint(
            method: e['method']! as String,
            path: e['path']! as String,
          ),
        )
        .toList();
    final String id = _snakeId(sample['id']! as String);
    final ProblemType generic = GenericProblems.all.singleWhere(
      (ProblemType t) => t.id == id,
    );
    final ProblemCatalog catalog = ProblemCatalog(
      portal: ErrorPortal(
        scheme: uri.scheme,
        host: uri.authority,
        landscape: path[1],
        platform: path[2],
        service: path[3],
        module: path[4],
      ),
    )..addType(generic, endpoints: endpoints);
    final Map<String, Object?> entry = catalog.lookup(id)!.toCrdContent();
    expect(entry.keys.toList(), shape);
    expect(entry['type'], type);
    for (final String key in <String>[
      'title',
      'status',
      'recoverable',
      'endpoints',
    ]) {
      expect(_canonical(entry[key]), _canonical(sample[key]), reason: key);
    }
  }
}

const Map<String, void Function(Map<String, Object?>)> _checks =
    <String, void Function(Map<String, Object?>)>{
      'envelopes.json': _checkEnvelopes,
      'type_uri.json': _checkTypeUri,
      'catalog_entry.json': _checkCatalogEntry,
    };

void main() {
  final Map<String, Object?> manifest = _object(
    jsonDecode(File('$_upstreamPath/manifest.json').readAsStringSync()),
  );
  final Map<String, Object?> vectors = _object(manifest['vectors']);

  test('manifest pins the source release and every checked vector', () {
    // Arrange
    final Map<String, Object?> source = _object(manifest['source']);

    // Act
    final Set<String> pinned = vectors.keys.toSet();

    // Assert
    expect(manifest['authority'], 'c0-fixtures-r2');
    expect(source['commit'], 'fe77520d591f81a9762c40ebf68dc9c0106502d3');
    expect(source['path'], 'contracts/c0/cases/problem.json');
    expect(pinned, _checks.keys.toSet());
    for (final Object? vector in vectors.values) {
      expect(_object(vector)['reproduce'], contains('jq -cS'));
      expect(_object(vector)['adaptations'], isNotEmpty);
    }
  });

  group('upstream Problem vectors', () {
    vectors.forEach((String name, Object? pin) {
      test(name, () {
        // Arrange
        final Object? vector = jsonDecode(
          File('$_upstreamPath/$name').readAsStringSync(),
        );

        // Act
        final String digest = sha256
            .convert(utf8.encode(_canonical(vector)))
            .toString();

        // Assert
        expect(
          digest,
          _object(pin)['sha256'],
          reason: 'upstream vector "$name" digest drifted from the manifest',
        );
        _checks[name]!(_object(vector));
      });
    });
  });
}
