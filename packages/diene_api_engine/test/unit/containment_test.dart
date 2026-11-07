import 'package:diene_api_engine/diene_api_engine.dart';
import 'package:diene_api_engine/src/generated/export.dart';
import 'package:diene_api_engine/test_helper.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

const LpsmCoordinate _coord = LpsmCoordinate(
  landscape: 'lapras',
  platform: 'lithium',
  service: 'api',
  module: 'root',
);

const String _fleet =
    '{"version":1,"catalogHosts":["cat.cluster.atomi.cloud"]}';

RescueConfig _rescue({
  List<String> seeds = const <String>['seed.cluster.atomi.cloud'],
}) => RescueConfig(
  enabled: true,
  issuer: Uri.parse('https://issuer.cluster.atomi.cloud'),
  catalogHosts: seeds,
  endpointSuffixAllowlist: const <String>['.cluster.atomi.cloud'],
);

RescueRouter _router(
  HttpTransport transport, {
  RescueConfig? config,
  Map<String, String>? seed,
}) => RescueRouter(
  config: config ?? _rescue(),
  store: InMemoryRescueStore(seed),
  transport: transport,
  sleep: noSleep,
  jitter: noJitter,
);

final RescueConfig _disabled = RescueConfig(
  enabled: false,
  issuer: Uri.parse('https://issuer.cluster.atomi.cloud'),
  catalogHosts: const <String>[],
  endpointSuffixAllowlist: const <String>[],
);

Received _ok(String body) => Received(HttpResponse(status: 200, body: body));

void main() {
  group('toResult never throws on a malformed problem body', () {
    test('a problem-shaped body with a non-string title is unexpected', () {
      // Arrange
      const Received outcome = Received(
        HttpResponse(status: 400, body: '{"type":"x","status":400,"title":5}'),
      );

      // Act
      final Result<int> result = toResult<int>(outcome, decode: (_) => 1);

      // Assert
      final Problem problem = expectProblemType(
        result,
        BridgeProblems.unexpectedResponse,
      );
      expect(problem.status, 400);
      expect(problem.data['body'], <String, Object?>{
        'type': 'x',
        'status': 400,
        'title': 5,
      });
    });
  });

  group('rescue never throws on a malformed document or store', () {
    test('a Doc A without a version is skipped like a bad host', () async {
      // Arrange
      final FakeHttpTransport transport = FakeHttpTransport(
        (HttpRequest request) =>
            _ok('{"catalogHosts":["cat.cluster.atomi.cloud"]}'),
      );

      // Act
      final RescueOutcome outcome = await _router(transport).rescue(_coord);

      // Assert
      expect(outcome, isA<RescueUnavailable>());
      expect(transport.sent.map((HttpRequest r) => r.url.path), <String>[
        '/fleet.json',
      ]);
    });

    test('a Doc A with an infinite version is skipped', () async {
      // Arrange
      final FakeHttpTransport transport = FakeHttpTransport(
        (HttpRequest request) =>
            _ok('{"version":1e400,"catalogHosts":["cat.cluster.atomi.cloud"]}'),
      );

      // Act
      final RescueOutcome outcome = await _router(transport).rescue(_coord);

      // Assert
      expect(outcome, isA<RescueUnavailable>());
      expect(transport.sent.map((HttpRequest r) => r.url.path), <String>[
        '/fleet.json',
      ]);
    });

    test('a Doc A with a whole-number double version is still used', () async {
      // Arrange
      final FakeHttpTransport transport = FakeHttpTransport(
        (HttpRequest request) => request.url.path == '/fleet.json'
            ? _ok('{"version":5.0,"catalogHosts":["cat.cluster.atomi.cloud"]}')
            : _ok(
                '{"version":1,"candidates":{"lapras.lithium.api.root":'
                '["https://alt.cluster.atomi.cloud"]}}',
              ),
      );

      // Act
      final RescueOutcome outcome = await _router(transport).rescue(_coord);

      // Assert
      expect((outcome as Rescued).baseUrl.host, 'alt.cluster.atomi.cloud');
    });

    test('a Doc A host that is not a URI is skipped', () async {
      // Arrange
      final FakeHttpTransport transport = FakeHttpTransport(
        (HttpRequest request) => request.url.path == '/fleet.json'
            ? _ok(
                '{"version":1,"catalogHosts":["[bad","cat.cluster.atomi.cloud"]}',
              )
            : _ok(
                '{"version":1,"candidates":{"lapras.lithium.api.root":'
                '["https://alt.cluster.atomi.cloud"]}}',
              ),
      );

      // Act
      final RescueOutcome outcome = await _router(transport).rescue(_coord);

      // Assert
      expect((outcome as Rescued).baseUrl.host, 'alt.cluster.atomi.cloud');
    });

    test('a baked seed that is not a URI is skipped', () async {
      // Arrange
      final FakeHttpTransport transport = FakeHttpTransport(
        (HttpRequest request) => _ok(_fleet),
      );
      final RescueRouter router = _router(
        transport,
        config: _rescue(
          seeds: const <String>['[bad', 'seed.cluster.atomi.cloud'],
        ),
      );

      // Act
      await router.rescue(_coord);

      // Assert
      expect(transport.sent.first.url.host, 'seed.cluster.atomi.cloud');
    });

    test('a Doc C candidate that is not a URI is skipped', () async {
      // Arrange
      final FakeHttpTransport transport = FakeHttpTransport(
        (HttpRequest request) => switch (request.url.path) {
          '/fleet.json' => _ok(_fleet),
          '/catalog/lithium.json' => _ok(
            '{"version":1,"candidates":{"lapras.lithium.api.root":'
            '["https://[bad","https://alt.cluster.atomi.cloud"]}}',
          ),
          _ => const Received(HttpResponse(status: 200)),
        },
      );

      // Act
      final RescueOutcome outcome = await _router(transport).rescue(_coord);

      // Assert
      expect((outcome as Rescued).baseUrl.host, 'alt.cluster.atomi.cloud');
    });

    test('a stored pin that is not a URI reads as no pin', () async {
      // Arrange
      final RescueRouter router = _router(
        FakeHttpTransport((HttpRequest request) => networkFailure()),
        seed: <String, String>{'pin.${_coord.key}': 'https://[bad'},
      );

      // Act
      final Uri? pin = await router.pinnedFor(_coord);

      // Assert
      expect(pin, isNull);
    });

    test('a stored last-known-good that is not a URI is not used', () async {
      // Arrange
      final RescueRouter router = _router(
        FakeHttpTransport((HttpRequest request) => networkFailure()),
        seed: <String, String>{'lastgood.${_coord.key}': 'https://[bad'},
      );

      // Act
      final RescueOutcome outcome = await router.rescue(_coord);

      // Assert
      expect(outcome, isA<RescueUnavailable>());
    });
  });

  group('ResultSdk never throws on an odd SDK failure', () {
    test(
      'a dio error that carries a 2xx response is a transport failure',
      () async {
        // Arrange
        final RequestOptions options = RequestOptions(path: '/users/1');
        Future<int> invoke() => throw DioException(
          requestOptions: options,
          response: Response<Object?>(
            requestOptions: options,
            statusCode: 200,
            data: <String, Object?>{'id': '1'},
          ),
        );

        // Act
        final Result<int> result = await const ResultSdk().call(invoke);

        // Assert
        final Problem problem = expectProblemType(
          result,
          BridgeProblems.transportFailure,
        );
        expect(problem.status, 200);
        expect(problem.detail, startsWith('decode failed'));
      },
    );

    test('a 2xx body the generated model cannot decode is an Err', () async {
      // Arrange
      final ApiEngine engine = ApiEngine.fromConfig(
        ApiEngineConfig(
          backends: <BackendConfig>[
            BackendConfig(
              coordinate: _coord,
              baseUrl: Uri.parse('https://api.lapras.cluster.atomi.cloud'),
            ),
          ],
          rescue: _disabled,
        ),
        transport: FakeHttpTransport(
          (HttpRequest request) => okJson(<String, Object?>{}),
        ),
      );
      final ServiceSdk sdk = engine.backend(_coord)!.sdk(ServiceSdk.new);

      // Act
      final Result<UserProfile> result = await const ResultSdk().call(
        () => sdk.users.getUser(id: '1'),
      );

      // Assert
      final Problem problem = expectProblemType(
        result,
        BridgeProblems.transportFailure,
      );
      expect(problem.detail, startsWith('SDK call threw'));
    });
  });
}
