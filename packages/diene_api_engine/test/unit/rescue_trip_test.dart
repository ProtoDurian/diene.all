import 'dart:io';

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
}
