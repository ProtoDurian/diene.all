import 'dart:io';
import 'dart:math';

import 'package:diene_api_engine/diene_api_engine.dart';
import 'package:diene_api_engine/test_helper.dart';
import 'package:flutter_test/flutter_test.dart';

const LpsmCoordinate _coord = LpsmCoordinate(
  landscape: 'lapras',
  platform: 'lithium',
  service: 'api',
  module: 'root',
);
const String _primary = 'api.lapras.cluster.atomi.cloud';
const String _docC =
    '{"version":3,"candidates":{"lapras.lithium.api.root":'
    '["https://alt.cluster.atomi.cloud"]}}';

RescueConfig _rescue({required bool enabled}) => RescueConfig(
  enabled: enabled,
  issuer: Uri.parse('https://issuer.cluster.atomi.cloud'),
  catalogHosts: const <String>['seed.cluster.atomi.cloud'],
  endpointSuffixAllowlist: const <String>['.cluster.atomi.cloud'],
);

Backend _backend(HttpTransport transport, {required bool enabled}) =>
    ApiEngine.fromConfig(
      ApiEngineConfig(
        backends: <BackendConfig>[
          BackendConfig(
            coordinate: _coord,
            baseUrl: Uri.parse('https://$_primary'),
          ),
        ],
        rescue: _rescue(enabled: enabled),
      ),
      transport: transport,
    ).backend(_coord)!;

Future<Result<Object?>> _get(Backend backend) => backend.call<Object?>(
  method: HttpMethod.get,
  path: '/users/1',
  decode: (Map<String, Object?> json) => json,
);

List<String> _hosts(FakeHttpTransport transport) =>
    transport.sent.map((HttpRequest r) => r.url.host).toList();

TransportOutcome _rescueDocs(HttpRequest request) => switch (request.url.path) {
  '/fleet.json' => Received(
    HttpResponse(
      status: 200,
      body: '{"version":1,"catalogHosts":["cat.cluster.atomi.cloud"]}',
    ),
  ),
  '/catalog/lithium.json' => const Received(
    HttpResponse(status: 200, body: _docC),
  ),
  _ => okJson(<String, Object?>{'id': '1'}),
};

void main() {
  group('rescue trips only on a hard failure that survives the retry', () {
    test('a received 5xx never enters the router', () async {
      // Arrange
      final FakeHttpTransport transport = FakeHttpTransport(
        (HttpRequest request) => nonJsonResponse(status: 503),
      );

      // Act
      final Result<Object?> result = await _get(
        _backend(transport, enabled: true),
      );

      // Assert
      expect(expectErr(result).status, 503);
      expect(_hosts(transport), <String>[_primary]);
    });

    test(
      'a network failure the retry recovers never enters the router',
      () async {
        // Arrange
        final FakeHttpTransport transport = FakeHttpTransport.sequence(
          <TransportOutcome>[
            networkFailure(),
            okJson(<String, Object?>{'id': '1'}),
          ],
        );

        // Act
        final Result<Object?> result = await _get(
          _backend(transport, enabled: true),
        );

        // Assert
        expectOk(result);
        expect(_hosts(transport), <String>[_primary, _primary]);
      },
    );

    test(
      'two network failures enter the router, then the rescued host',
      () async {
        // Arrange
        final FakeHttpTransport transport = FakeHttpTransport(
          (HttpRequest request) => request.url.host == _primary
              ? networkFailure()
              : _rescueDocs(request),
        );

        // Act
        final Result<Object?> result = await _get(
          _backend(transport, enabled: true),
        );

        // Assert
        expectOk(result);
        expect(_hosts(transport), <String>[
          _primary,
          _primary,
          'seed.cluster.atomi.cloud',
          'cat.cluster.atomi.cloud',
          'alt.cluster.atomi.cloud',
          'alt.cluster.atomi.cloud',
        ]);
      },
    );

    test('a disabled context never builds or enters a router', () async {
      // Arrange
      final FakeHttpTransport transport = FakeHttpTransport(
        (HttpRequest request) => networkFailure(),
      );
      final Backend backend = _backend(transport, enabled: false);

      // Act
      final Result<Object?> result = await _get(backend);

      // Assert
      expectProblemType(result, BridgeProblems.transportFailure);
      expect(_hosts(transport), <String>[_primary, _primary]);
    });
  });

  group('disk cache', () {
    test('a Doc C cached on disk is used after a restart', () async {
      // Arrange
      final Directory dir = Directory.systemTemp.createTempSync('rescue');
      addTearDown(() => dir.deleteSync(recursive: true));
      await RescueRouter(
        config: _rescue(enabled: true),
        store: FileRescueStore(dir),
        transport: FakeHttpTransport(_rescueDocs),
        sleep: noSleep,
        jitter: noJitter,
      ).rescue(_coord);
      await FileRescueStore(dir).delete('pin.${_coord.key}');
      await FileRescueStore(dir).delete('lastgood.${_coord.key}');
      final FakeHttpTransport offline = FakeHttpTransport(
        (HttpRequest request) => request.url.path == '/fleet.json'
            ? networkFailure()
            : okJson(<String, Object?>{}),
      );

      // Act
      final RescueOutcome outcome = await RescueRouter(
        config: _rescue(enabled: true),
        store: FileRescueStore(dir),
        transport: offline,
        sleep: noSleep,
        jitter: noJitter,
      ).rescue(_coord);

      // Assert
      final Rescued rescued = outcome as Rescued;
      expect(rescued.baseUrl.host, 'alt.cluster.atomi.cloud');
      expect(rescued.fromLastKnownGood, isFalse);
    });
  });

  group('monotonic Doc A', () {
    test('a Doc A older than the one seen is refused', () async {
      // Arrange
      final FakeRescueStore store = FakeRescueStore(<String, String>{
        'doca.version': '5',
      });
      final FakeHttpTransport transport = FakeHttpTransport(_rescueDocs);

      // Act
      final RescueOutcome outcome = await RescueRouter(
        config: _rescue(enabled: true),
        store: store,
        transport: transport,
        sleep: noSleep,
        jitter: noJitter,
      ).rescue(_coord);

      // Assert
      expect(outcome, isA<RescueUnavailable>());
      expect(_hosts(transport), <String>['seed.cluster.atomi.cloud']);
      expect(await store.read('doca.version'), '5');
    });
  });

  group('jittered scan', () {
    const List<String> hosts = <String>[
      'c0.cluster.atomi.cloud',
      'c1.cluster.atomi.cloud',
      'c2.cluster.atomi.cloud',
      'c3.cluster.atomi.cloud',
      'c4.cluster.atomi.cloud',
      'c5.cluster.atomi.cloud',
    ];
    final String cachedDocC = DocC(
      version: 1,
      candidates: <String, List<String>>{
        _coord.key: <String>[for (final String h in hosts) 'https://$h'],
      },
    ).encode();

    InMemoryRescueStore store() => InMemoryRescueStore(<String, String>{
      'docc.lithium.lapras': cachedDocC,
      'docc.version.lithium.lapras': '1',
    });

    RescueConfig config({Duration budget = const Duration(seconds: 8)}) =>
        RescueConfig(
          enabled: true,
          issuer: Uri.parse('https://issuer.cluster.atomi.cloud'),
          catalogHosts: const <String>[],
          endpointSuffixAllowlist: const <String>['.cluster.atomi.cloud'],
          scanBudget: budget,
        );

    test('a random jitter in range is slept before every probe', () async {
      // Arrange
      final List<String> log = <String>[];
      final FakeHttpTransport transport = FakeHttpTransport((
        HttpRequest request,
      ) {
        log.add('probe ${request.url.host}');
        return nonJsonResponse(status: 503);
      });
      final RescueRouter router = RescueRouter(
        config: config(),
        store: store(),
        transport: transport,
        sleep: (Duration d) async => log.add('sleep ${d.inMilliseconds}'),
        nowMs: () => 0,
        random: Random(42),
      );

      // Act
      final RescueOutcome outcome = await router.rescue(_coord);

      // Assert
      expect(outcome, isA<RescueUnavailable>());
      final List<int> jitters = <int>[];
      for (int i = 0; i < hosts.length; i++) {
        final List<String> step = log.sublist(i * 3, i * 3 + 3);
        final int ms = int.parse(step[0].split(' ').last);
        expect(step[0], startsWith('sleep '));
        expect(ms, inInclusiveRange(0, 250));
        expect(step.sublist(1), <String>['probe ${hosts[i]}', 'sleep 3000']);
        jitters.add(ms);
      }
      expect(log, hasLength(hosts.length * 3));
      expect(jitters.toSet().length, greaterThan(1));
    });

    test('a jitter that uses up the budget leaves no probe', () async {
      // Arrange
      final FakeClock clock = FakeClock();
      final FakeHttpTransport transport = FakeHttpTransport(
        (HttpRequest request) => okJson(<String, Object?>{}),
      );
      final RescueRouter router = RescueRouter(
        config: config(budget: const Duration(milliseconds: 100)),
        store: store(),
        transport: transport,
        sleep: clock.sleep,
        nowMs: clock.nowMs,
        jitter: () => const Duration(milliseconds: 100),
      );

      // Act
      final RescueOutcome outcome = await router.rescue(_coord);

      // Assert
      expect(outcome, isA<RescueUnavailable>());
      expect(transport.sent, isEmpty);
      expect(clock.nowMs(), 100);
    });

    test('the probe after a jitter gets only the budget left', () async {
      // Arrange
      final FakeClock clock = FakeClock();
      final List<int> sleeps = <int>[];
      final RescueRouter router = RescueRouter(
        config: config(budget: const Duration(milliseconds: 100)),
        store: store(),
        transport: HangingTransport(),
        sleep: (Duration d) {
          sleeps.add(d.inMilliseconds);
          return clock.sleep(d);
        },
        nowMs: clock.nowMs,
        jitter: () => const Duration(milliseconds: 99),
      );

      // Act
      final RescueOutcome outcome = await router.rescue(_coord);

      // Assert
      expect(outcome, isA<RescueUnavailable>());
      expect(sleeps.take(3), <int>[99, 1, 99]);
      expect(clock.nowMs(), 199);
    });
  });

  group('use-time allowlist on stored addresses', () {
    test('a stored pin on a foreign host is ignored', () async {
      // Arrange
      final FakeHttpTransport transport = FakeHttpTransport(
        (HttpRequest request) => okJson(<String, Object?>{'id': '1'}),
      );
      final ApiEngine engine = ApiEngine.fromConfig(
        ApiEngineConfig(
          backends: <BackendConfig>[
            BackendConfig(
              coordinate: _coord,
              baseUrl: Uri.parse('https://$_primary'),
            ),
          ],
          rescue: _rescue(enabled: true),
        ),
        transport: transport,
        store: InMemoryRescueStore(<String, String>{
          'pin.${_coord.key}': 'https://evil.example.com',
        }),
      );

      // Act
      final Uri? pin = await engine.rescue!.pinnedFor(_coord);
      final Result<Object?> result = await _get(engine.backend(_coord)!);

      // Assert
      expect(pin, isNull);
      expectOk(result);
      expect(_hosts(transport), <String>[_primary]);
    });

    test('a stored last-known-good on a foreign host is not used', () async {
      // Arrange
      final RescueRouter router = RescueRouter(
        config: _rescue(enabled: true),
        store: InMemoryRescueStore(<String, String>{
          'lastgood.${_coord.key}': 'https://evil.example.com',
        }),
        transport: FakeHttpTransport((HttpRequest request) => networkFailure()),
        sleep: noSleep,
        jitter: noJitter,
      );

      // Act
      final RescueOutcome outcome = await router.rescue(_coord);

      // Assert
      expect(outcome, isA<RescueUnavailable>());
    });
  });
}
