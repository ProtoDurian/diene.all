import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:diene_api_engine/diene_api_engine.dart';
import 'package:diene_api_engine/src/generated/export.dart';
import 'package:diene_api_engine/test_helper.dart';
import 'package:flutter_test/flutter_test.dart';

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

Object? _readJson(String name) =>
    jsonDecode(File('$_upstreamPath/$name').readAsStringSync());

final RescueConfig _noRescue = RescueConfig(
  enabled: false,
  issuer: Uri.parse('https://issuer.cluster.atomi.cloud'),
  catalogHosts: const <String>[],
  endpointSuffixAllowlist: const <String>[],
);

LpsmCoordinate _coord(Map<String, Object?> sample) => LpsmCoordinate(
  landscape: sample['landscape']! as String,
  platform: sample['platform']! as String,
  service: sample['service']! as String,
  module: 'web',
);

Backend _backend(
  HttpTransport transport, {
  LpsmCoordinate coordinate = const LpsmCoordinate(
    landscape: 'raichu',
    platform: 'dotnet',
    service: 'user',
    module: 'api',
  ),
  String? resourceName,
  IAuth? auth,
}) => ApiEngine.fromConfig(
  ApiEngineConfig(
    backends: <BackendConfig>[
      BackendConfig(
        coordinate: coordinate,
        baseUrl: Uri.parse('https://api.raichu.cluster.atomi.cloud'),
        resourceName: resourceName,
      ),
    ],
    rescue: _noRescue,
  ),
  auth: auth,
  transport: transport,
).backend(coordinate)!;

Received _serve(Map<String, Object?> body, int status) =>
    Received(HttpResponse(status: status, body: jsonEncode(body)));

void main() {
  final Map<String, Object?> manifest = _object(_readJson('manifest.json'));
  final Map<String, Object?> vectors = _object(manifest['vectors']);

  test('the manifest pins the upstream cases this engine uses', () {
    // Arrange
    final Map<String, Object?> sources = _object(manifest['sources']);

    // Act
    final Set<String> vendored = Directory(_upstreamPath)
        .listSync()
        .map((FileSystemEntity f) => f.uri.pathSegments.last)
        .where((String f) => f != 'manifest.json')
        .toSet();

    // Assert
    expect(vendored, vectors.keys.toSet());
    expect(manifest['authority'], 'c0-fixtures-r2');
    expect(manifest['commit'], 'fe77520d591f81a9762c40ebf68dc9c0106502d3');
    expect(sources.keys.toSet(), <String>{
      'contracts/c0/cases/identity.json',
      'contracts/c0/cases/problem.json',
    });
    for (final Object? raw in vectors.values) {
      expect(sources.keys, contains(_object(raw)['path']));
    }
    expect(vectors.keys.toSet(), <String>{
      'problem_envelopes.json',
      'problem_extensions.json',
      'problem_members.json',
      'resource_audience.json',
    });
  });

  group('upstream vector digests', () {
    vectors.forEach((String name, Object? raw) {
      test(name, () {
        // Arrange
        final Map<String, Object?> entry = _object(raw);

        // Act
        final String digest = sha256
            .convert(utf8.encode(_canonical(_readJson(name))))
            .toString();

        // Assert
        expect(
          digest,
          entry['sha256'],
          reason: 'upstream vector "$name" digest drifted from the manifest',
        );
      });

      test('$name file bytes', () {
        // Arrange
        final Map<String, Object?> entry = _object(raw);

        // Act
        final String digest = sha256
            .convert(File('$_upstreamPath/$name').readAsBytesSync())
            .toString();

        // Assert
        expect(
          digest,
          entry['fileSha256'],
          reason: 'upstream vector "$name" bytes drifted from the manifest',
        );
      });
    });
  });

  group('problem envelopes', () {
    final Map<String, Object?> envelopes = _object(
      _readJson('problem_envelopes.json'),
    );
    final List<Map<String, Object?>> valid = _objects(envelopes['valid']);

    test('the upstream set has valid envelopes and no invalid ones', () {
      // Arrange
      final List<Object?> invalid = envelopes['invalid']! as List<Object?>;

      // Act
      final int count = valid.length;

      // Assert
      expect(count, greaterThan(0));
      expect(invalid, isEmpty);
    });

    for (final Map<String, Object?> envelope in valid) {
      final int status = envelope['status']! as int;

      test('toResult returns the envelope at $status as that Problem', () {
        // Arrange
        final Received outcome = _serve(envelope, status);

        // Act
        final Result<Object?> result = toResult<Object?>(
          outcome,
          decode: (Map<String, Object?> json) => json,
        );

        // Assert
        final Problem problem = expectErr(result);
        expect(_canonical(problem.toJson()), _canonical(envelope));
        expect(problem.data, envelope['data']);
      });

      test('the same envelope at 500 is still that Problem', () {
        // Arrange
        final Received outcome = _serve(envelope, 500);

        // Act
        final Result<Object?> result = toResult<Object?>(
          outcome,
          decode: (Map<String, Object?> json) => json,
        );

        // Assert
        expect(_canonical(expectErr(result).toJson()), _canonical(envelope));
      });

      test(
        'a generated SDK call returns the envelope as that Problem',
        () async {
          // Arrange
          final ServiceSdk sdk = _backend(
            FakeHttpTransport(
              (HttpRequest request) => _serve(envelope, status),
            ),
          ).sdk(ServiceSdk.new);

          // Act
          final Result<UserProfile> result = await const ResultSdk().call(
            () => sdk.users.getUser(id: '42'),
          );

          // Assert
          expect(_canonical(expectErr(result).toJson()), _canonical(envelope));
        },
      );
    }
  });

  group('problem members', () {
    final Set<String> members =
        (_readJson('problem_members.json')! as List<Object?>)
            .cast<String>()
            .toSet();
    final Set<String> extensions =
        (_readJson('problem_extensions.json')! as List<Object?>)
            .cast<String>()
            .toSet();

    test('every engine problem uses only the allowed members', () async {
      // Arrange
      final ClientTree tree = ClientTree();
      final BackendConfig backend = BackendConfig(
        coordinate: const LpsmCoordinate(
          landscape: 'raichu',
          platform: 'dotnet',
          service: 'user',
          module: 'api',
        ),
        baseUrl: Uri.parse('https://api.raichu.cluster.atomi.cloud'),
      );
      tree.register(backend);

      // Act
      final List<Problem> problems = <Problem>[
        expectErr(toResult<int>(networkFailure(), decode: (_) => 1)),
        expectErr(toResult<int>(nonJsonResponse(), decode: (_) => 1)),
        expectErr(
          toResult<int>(
            nonProblemJson(<String, Object?>{'e': 1}),
            decode: (_) => 1,
          ),
        ),
        expectErr(
          toResult<int>(
            okJson(<String, Object?>{}),
            decode: (_) => throw StateError('x'),
          ),
        ),
        expectErr(tree.register(backend)),
        expectErr(
          await _backend(
            FakeHttpTransport(
              (HttpRequest request) => okJson(<String, Object?>{}),
            ),
            resourceName: 'root',
            auth: FakeAuth(const <String, String>{}),
          ).call<int>(method: HttpMethod.get, path: '/', decode: (_) => 1),
        ),
      ];

      // Assert
      for (final Problem problem in problems) {
        final Map<String, Object?> json = problem.toJson();
        expect(
          members.union(extensions),
          containsAll(json.keys),
          reason: '$problem',
        );
        expect(json.keys, containsAll(<String>['type', 'title', 'status']));
        expect(json.values, isNot(contains(null)), reason: '$problem');
      }
    });

    test('an absent optional member is omitted, not null', () {
      // Arrange
      final Map<String, Object?> envelope = <String, Object?>{
        'type': 'urn:diene:problem:conflict',
        'title': 'Conflict',
        'status': 409,
      };

      // Act
      final Problem problem = expectErr(
        toResult<int>(_serve(envelope, 409), decode: (_) => 1),
      );

      // Assert
      expect(problem.toJson().containsKey('detail'), isFalse);
      expect(problem.toJson().containsKey('instance'), isFalse);
      expect(members, containsAll(<String>['detail', 'instance']));
    });
  });

  group('resource audience', () {
    final Map<String, Object?> audience = _object(
      _readJson('resource_audience.json'),
    );
    final Map<String, Object?> samples = _object(audience['vectors']);

    String fill(String template, Map<String, Object?> sample) =>
        <String>['resourceName', 'service', 'platform', 'landscape'].fold(
          template,
          (String t, String k) => t.replaceAll('{$k}', '${sample[k]}'),
        );

    for (final Map<String, Object?> sample in _objects(samples['valid'])) {
      test('valid ${sample['name']}: the backend asks for that key', () async {
        // Arrange
        final String mapKey = sample['expectedMapKey']! as String;
        final FakeHttpTransport transport = FakeHttpTransport(
          (HttpRequest request) => okJson(<String, Object?>{}),
        );
        final FakeAuth auth = FakeAuth(<String, String>{mapKey: 'tok'});
        final Backend backend = _backend(
          transport,
          coordinate: _coord(sample),
          resourceName: sample['resourceName']! as String,
          auth: auth,
        );

        // Act
        final ResourceKey key = backend.resourceKey!;
        await backend.call<int>(
          method: HttpMethod.get,
          path: '/',
          decode: (_) => 1,
        );

        // Assert
        expect(key.mapKey, mapKey);
        expect(key.mapKey, fill(audience['mapKeyTemplate']! as String, sample));
        expect(key.audience.toString(), sample['expectedAudience']);
        expect(
          key.audience.toString(),
          fill(audience['audienceTemplate']! as String, sample),
        );
        expect(auth.queried, <String>[mapKey]);
        expect(transport.sent.single.headers['Authorization'], 'Bearer tok');
      });
    }

    for (final Map<String, Object?> sample in _objects(samples['invalid'])) {
      test('invalid ${sample['name']}: the resource key fails', () {
        // Arrange
        final Backend backend = _backend(
          FakeHttpTransport((HttpRequest request) => networkFailure()),
          coordinate: _coord(sample),
          resourceName: sample['resourceName']! as String,
          auth: FakeAuth(const <String, String>{}),
        );

        // Act
        ResourceKey? act() => backend.resourceKey;

        // Assert
        expect(act, throwsFormatException);
      });
    }
  });
}
