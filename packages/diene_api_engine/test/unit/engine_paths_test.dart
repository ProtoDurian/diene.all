library;

import 'package:diene_api_engine/diene_api_engine.dart';
import 'package:diene_api_engine/test_helper.dart';
import 'package:flutter_test/flutter_test.dart';

LpsmCoordinate _coord(String module) => LpsmCoordinate(
  landscape: 'lapras',
  platform: 'platform',
  service: 'service',
  module: module,
);

Map<String, Object?> _id(Map<String, Object?> json) => json;

RescueConfig _liveRescue() => RescueConfig(
  enabled: true,
  issuer: Uri.parse('https://auth.lapras.cluster.atomi.cloud'),
  catalogHosts: const <String>['https://seed.example.com'],
  endpointSuffixAllowlist: const <String>['.example.com'],
);

RescueConfig _disabledRescue() => RescueConfig(
  enabled: false,
  issuer: Uri.parse('https://unused.example'),
  catalogHosts: const <String>[],
  endpointSuffixAllowlist: const <String>[],
);

ApiEngineConfig _config(RescueConfig rescue) => ApiEngineConfig(
  backends: <BackendConfig>[
    BackendConfig(
      coordinate: _coord('a'),
      baseUrl: Uri.parse('https://primary.example.com'),
      resourceName: 'a',
    ),
  ],
  rescue: rescue,
);

void main() {
  group('pin-until-primary-heals', () {
    test('a healthy primary response while pinned CLEARS the pin', () async {
      // Arrange
      final FakeRescueStore store = FakeRescueStore(<String, String>{
        'pin.${_coord('a').key}': 'https://rescue.example.com',
      });
      final FakeHttpTransport transport = FakeHttpTransport(
        (HttpRequest _) => okJson(<String, Object?>{'ok': true}),
      );
      final RescueRouter router = RescueRouter(
        config: _liveRescue(),
        store: store,
        transport: transport,
        sleep: noSleep,
        jitter: noJitter,
        nowMs: FakeClock().nowMs,
      );
      final ApiEngine engine = ApiEngine.fromConfig(
        _config(_liveRescue()),
        auth: FakeAuth(<String, String>{'platform/lapras/service/a': 'tok-a'}),
        transport: transport,
        rescueOverride: router,
      );

      // Act
      final Result<Map<String, Object?>> result = await engine
          .backend(_coord('a'))!
          .call<Map<String, Object?>>(
            method: HttpMethod.get,
            path: '/thing',
            decode: _id,
          );

      // Assert
      expect(result.isOk, isTrue);
      expect(await router.pinnedFor(_coord('a')), isNull);
    });

    test('a 5xx while pinned does NOT clear the pin', () async {
      // Arrange
      final FakeRescueStore store = FakeRescueStore(<String, String>{
        'pin.${_coord('a').key}': 'https://rescue.example.com',
      });
      final FakeHttpTransport transport = FakeHttpTransport(
        (HttpRequest _) =>
            const Received(HttpResponse(status: 503, body: '{}')),
      );
      final RescueRouter router = RescueRouter(
        config: _liveRescue(),
        store: store,
        transport: transport,
        sleep: noSleep,
        jitter: noJitter,
        nowMs: FakeClock().nowMs,
      );
      final ApiEngine engine = ApiEngine.fromConfig(
        _config(_liveRescue()),
        transport: transport,
        rescueOverride: router,
      );

      // Act
      final Result<Map<String, Object?>> result = await engine
          .backend(_coord('a'))!
          .call<Map<String, Object?>>(
            method: HttpMethod.get,
            path: '/thing',
            decode: _id,
          );

      // Assert
      expect(result.isErr, isTrue);
      expect(
        await router.pinnedFor(_coord('a')),
        Uri.parse('https://rescue.example.com'),
      );
    });
  });

  group('rescue trip', () {
    test(
      'a hard failure with NO router returns the transport reason',
      () async {
        // Arrange
        final FakeHttpTransport transport = FakeHttpTransport(
          (HttpRequest _) => networkFailure('connection refused'),
        );
        final ApiEngine engine = ApiEngine.fromConfig(
          _config(_disabledRescue()),
          transport: transport,
        );

        // Act
        final Result<Map<String, Object?>> result = await engine
            .backend(_coord('a'))!
            .call<Map<String, Object?>>(
              method: HttpMethod.get,
              path: '/thing',
              decode: _id,
            );

        // Assert
        final Problem problem = expectErr(result);
        expect(problem.type, BridgeProblems.transportFailure);
        expect(problem.data['reason'], contains('connection refused'));
        expect(engine.rescue, isNull);
      },
    );

    test(
      'a router that cannot rescue still reports the ORIGINAL failure',
      () async {
        // Arrange
        final FakeHttpTransport transport = FakeHttpTransport(
          (HttpRequest _) => networkFailure('primary down'),
        );
        final RescueRouter router = RescueRouter(
          config: _liveRescue(),
          store: FakeRescueStore(),
          transport: transport,
          sleep: noSleep,
          jitter: noJitter,
          nowMs: FakeClock().nowMs,
        );
        final ApiEngine engine = ApiEngine.fromConfig(
          _config(_liveRescue()),
          transport: transport,
          rescueOverride: router,
        );

        // Act
        final Result<Map<String, Object?>> result = await engine
            .backend(_coord('a'))!
            .call<Map<String, Object?>>(
              method: HttpMethod.get,
              path: '/thing',
              decode: _id,
            );

        // Assert
        expect(expectErr(result).data['reason'], contains('primary down'));
      },
    );
  });

  group('request building', () {
    test(
      'query parameters merge onto a base that already carries some',
      () async {
        // Arrange
        final FakeHttpTransport transport = FakeHttpTransport(
          (HttpRequest _) => okJson(<String, Object?>{'ok': true}),
        );
        final ApiEngineConfig config = ApiEngineConfig(
          backends: <BackendConfig>[
            BackendConfig(
              coordinate: _coord('a'),

              baseUrl: Uri.parse(
                'https://primary.example.com/api/?tenant=acme',
              ),
            ),
          ],
          rescue: _disabledRescue(),
        );
        final ApiEngine engine = ApiEngine.fromConfig(
          config,
          transport: transport,
        );

        // Act
        await engine
            .backend(_coord('a'))!
            .call<Map<String, Object?>>(
              method: HttpMethod.get,
              path: '/thing',
              query: <String, String>{'page': '2'},
              decode: _id,
            );

        // Assert
        final Uri sent = transport.sent.single.url;
        expect(sent.queryParameters['tenant'], 'acme');
        expect(sent.queryParameters['page'], '2');

        expect(sent.path, '/api/thing');
      },
    );

    test('headers and a body are carried onto the request', () async {
      // Arrange
      final FakeHttpTransport transport = FakeHttpTransport(
        (HttpRequest _) => okJson(<String, Object?>{'ok': true}),
      );
      final ApiEngine engine = ApiEngine.fromConfig(
        _config(_disabledRescue()),
        transport: transport,
      );

      // Act
      await engine
          .backend(_coord('a'))!
          .call<Map<String, Object?>>(
            method: HttpMethod.post,
            path: '/thing',
            headers: <String, String>{'x-trace': 'abc'},
            body: '{"a":1}',
            decode: _id,
          );

      // Assert
      final HttpRequest sent = transport.sent.single;
      expect(sent.headers['x-trace'], 'abc');
      expect(sent.body, '{"a":1}');
      expect(sent.method, HttpMethod.post);
    });
  });

  group('ApiEngine.fromConfig default construction', () {
    test('with rescue ENABLED and no override it builds its own router', () {
      // Arrange
      // Act
      final ApiEngine engine = ApiEngine.fromConfig(_config(_liveRescue()));

      // Assert
      expect(engine.rescue, isNotNull);
      expect(engine.rescue!.bakedIssuer, _liveRescue().issuer);
      expect(engine.tree.contains(_coord('a')), isTrue);
    });

    test('a duplicate coordinate throws a StateError naming the conflict', () {
      // Arrange
      final ApiEngineConfig dupes = ApiEngineConfig(
        backends: <BackendConfig>[
          BackendConfig(
            coordinate: _coord('a'),
            baseUrl: Uri.parse('https://one.example.com'),
          ),
          BackendConfig(
            coordinate: _coord('a'),
            baseUrl: Uri.parse('https://two.example.com'),
          ),
        ],
        rescue: _disabledRescue(),
      );

      // Act
      // Assert
      expect(
        () => ApiEngine.fromConfig(dupes),
        throwsA(
          isA<StateError>().having(
            (StateError e) => e.message,
            'message',
            contains('backend registration failed'),
          ),
        ),
      );
    });
  });

  group('client tree', () {
    test('resolve returns null for an unregistered coordinate', () {
      // Arrange
      final ApiEngine engine = ApiEngine.fromConfig(_config(_disabledRescue()));

      // Act
      // Assert
      expect(engine.backend(_coord('nope')), isNull);
      expect(engine.tree.resolve(_coord('nope')), isNull);
      expect(engine.tree.contains(_coord('nope')), isFalse);
    });
  });
}
