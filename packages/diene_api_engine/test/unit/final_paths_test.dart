library;

import 'dart:convert';

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

void main() {
  group('rescue second attempt', () {
    test(
      'a rescued address that ALSO fails reports the second failure',
      () async {
        // Arrange
        final FakeRescueStore store = FakeRescueStore();
        final RescueConfig rescue = RescueConfig(
          enabled: true,
          issuer: Uri.parse('https://auth.example.com'),
          catalogHosts: const <String>['https://seed.example.com'],
          endpointSuffixAllowlist: const <String>['.example.com'],
        );

        await store.write(
          'doca',
          jsonEncode(<String, Object?>{
            'version': 1,
            'catalogHosts': <String>['https://seed.example.com'],
          }),
        );
        await store.write(
          'docc.${_coord('a').platform}.${_coord('a').landscape}',
          jsonEncode(<String, Object?>{
            'version': 1,
            'candidates': <String, Object?>{
              _coord('a').key: <String>['https://rescue.example.com'],
            },
          }),
        );

        int calls = 0;
        final FakeHttpTransport transport = FakeHttpTransport((
          HttpRequest req,
        ) {
          calls += 1;
          if (req.method == HttpMethod.head) {
            return Received(const HttpResponse(status: 200, body: ''));
          }

          return networkFailure('rescued host also refused');
        });

        final ApiEngine engine = ApiEngine.fromConfig(
          ApiEngineConfig(
            backends: <BackendConfig>[
              BackendConfig(
                coordinate: _coord('a'),
                baseUrl: Uri.parse('https://primary.example.com'),
                retryOnNetworkError: false,
              ),
            ],
            rescue: rescue,
          ),
          transport: transport,
          rescueOverride: RescueRouter(
            config: rescue,
            store: store,
            transport: transport,
            sleep: noSleep,
            jitter: noJitter,
            nowMs: FakeClock().nowMs,
          ),
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
        expect(calls, greaterThan(1), reason: 'the rescue path was exercised');
      },
    );
  });

  group('config type validation', () {
    Map<String, Object?> backend(Map<String, Object?> overrides) =>
        <String, Object?>{
          'backends': <Object?>[
            <String, Object?>{
              'baseUrl': 'https://a.example.com',
              'coordinate': <String, Object?>{
                'landscape': 'lapras',
                'platform': 'platform',
                'service': 'service',
                'module': 'core',
              },
              ...overrides,
            },
          ],
          'rescue': <String, Object?>{
            'enabled': false,
            'issuer': 'https://auth.example.com',
            'catalogHosts': <String>[],
            'endpointSuffixAllowlist': <String>[],
          },
        };

    test('a NON-STRING where a string is required throws FormatException', () {
      // Arrange
      // Act
      // Assert
      expect(
        () =>
            ApiEngineConfig.fromMap(backend(<String, Object?>{'baseUrl': 42})),
        throwsA(isA<FormatException>()),
      );
    });

    test('an EMPTY string is rejected as well as a wrong type', () {
      // Arrange
      // Act
      // Assert
      expect(
        () =>
            ApiEngineConfig.fromMap(backend(<String, Object?>{'baseUrl': ''})),
        throwsA(isA<FormatException>()),
      );
    });

    test('a non-string coordinate label is rejected too', () {
      // Arrange
      // Act
      // Assert
      expect(
        () => ApiEngineConfig.fromMap(
          backend(<String, Object?>{
            'coordinate': <String, Object?>{
              'landscape': <String>['not', 'a', 'string'],
              'platform': 'platform',
              'service': 'service',
              'module': 'core',
            },
          }),
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('a well-formed map DOES parse, so the guards are not blanket', () {
      // Arrange
      // Act
      final ApiEngineConfig config = ApiEngineConfig.fromMap(
        backend(const <String, Object?>{}),
      );

      // Assert
      expect(config.backends.single.coordinate.module, 'core');
    });
  });

  group('fetched document decoding', () {
    test(
      'a FETCHED document that is invalid JSON is treated as absent',
      () async {
        // Arrange
        final RescueConfig rescue = RescueConfig(
          enabled: true,
          issuer: Uri.parse('https://auth.example.com'),
          catalogHosts: const <String>['https://seed.example.com'],
          endpointSuffixAllowlist: const <String>['.example.com'],
        );
        final FakeHttpTransport transport = FakeHttpTransport(
          (HttpRequest _) => Received(
            const HttpResponse(status: 200, body: '{not json at all'),
          ),
        );
        final RescueRouter router = RescueRouter(
          config: rescue,
          store: FakeRescueStore(),
          transport: transport,
          sleep: noSleep,
          jitter: noJitter,
          nowMs: FakeClock().nowMs,
        );

        // Act
        final RescueOutcome outcome = await router.rescue(_coord('a'));

        // Assert
        expect(outcome, isA<RescueUnavailable>());

        expect(transport.sent, isNotEmpty);
      },
    );
  });
}
