library;

import 'package:diene_api_engine/diene_api_engine.dart';
import 'package:diene_api_engine/test_helper.dart';
import 'package:flutter_test/flutter_test.dart';

class _ThrowingTransport implements HttpTransport {
  int calls = 0;

  @override
  Future<TransportOutcome> send(HttpRequest request) async {
    calls += 1;
    throw StateError('transport contract violated');
  }
}

class _ProbeThrowingTransport implements HttpTransport {
  int heads = 0;

  @override
  Future<TransportOutcome> send(HttpRequest request) async {
    if (request.method == HttpMethod.head) {
      heads += 1;
      throw StateError('probe transport threw');
    }
    if (request.url.path == '/fleet.json') {
      return Received(
        const HttpResponse(
          status: 200,
          body: '{"version":1,"catalogHosts":["seed.example.com"]}',
        ),
      );
    }
    return Received(
      const HttpResponse(
        status: 200,
        body:
            '{"version":1,"candidates":'
            '{"lapras.platform.service.core":["https://r.example.com"]}}',
      ),
    );
  }
}

class _PartiallyThrowingTransport implements HttpTransport {
  _PartiallyThrowingTransport(this._throwOnHost, this._responder);

  final String _throwOnHost;
  final TransportOutcome Function(HttpRequest request) _responder;
  final List<Uri> sent = <Uri>[];

  @override
  Future<TransportOutcome> send(HttpRequest request) async {
    sent.add(request.url);
    if (request.url.host == _throwOnHost) {
      throw StateError('this mirror is broken');
    }
    return _responder(request);
  }
}

const LpsmCoordinate _core = LpsmCoordinate(
  landscape: 'lapras',
  platform: 'platform',
  service: 'service',
  module: 'core',
);

RescueRouter _router(HttpTransport transport, {List<String>? hosts}) =>
    RescueRouter(
      config: RescueConfig(
        enabled: true,
        issuer: Uri.parse('https://auth.example.com'),
        catalogHosts: hosts ?? const <String>['https://seed.example.com'],
        endpointSuffixAllowlist: const <String>['.example.com'],
      ),
      store: FakeRescueStore(),
      transport: transport,
      sleep: noSleep,
      jitter: noJitter,
      nowMs: FakeClock().nowMs,
    );

void main() {
  group('containment lives at ONE point per path', () {
    test('probeHealthy REJECTS — it does not contain, by design', () async {
      // Arrange
      // Act
      // Assert
      await expectLater(
        _router(
          _ThrowingTransport(),
        ).probeHealthy(Uri.parse('https://a.example.com')),
        throwsA(isA<StateError>()),
      );
    });

    test(
      'a throwing PROBE is contained by the onError arm, not propagated',
      () async {
        // Arrange
        final _ProbeThrowingTransport transport = _ProbeThrowingTransport();

        // Act
        final RescueOutcome outcome = await _router(transport).rescue(_core);

        // Assert
        expect(outcome, isA<RescueUnavailable>());

        expect(transport.heads, greaterThan(0));
      },
    );

    test('a throwing FETCH is contained by _sendOrNull', () async {
      // Arrange
      final _ThrowingTransport transport = _ThrowingTransport();

      // Act
      final RescueOutcome outcome = await _router(transport).rescue(_core);

      // Assert
      expect(outcome, isA<RescueUnavailable>());
      expect((outcome as RescueUnavailable).reason, isNotEmpty);
      expect(transport.calls, greaterThan(0));
    });

    test(
      'a WELL-BEHAVED transport still works, so nothing was broken to fix it',
      () async {
        // Arrange
        // Act
        final RescueOutcome outcome = await _router(
          FakeHttpTransport((HttpRequest _) => networkFailure('down')),
        ).rescue(_core);

        // Assert
        expect(outcome, isA<RescueUnavailable>());
      },
    );
  });

  group('fetch containment is scoped PER HOST, not per scan', () {
    test(
      'one throwing mirror does not abort a scan another seed can satisfy',
      () async {
        // Arrange
        final _PartiallyThrowingTransport transport =
            _PartiallyThrowingTransport('broken.example.com', (HttpRequest r) {
              if (r.url.path == '/fleet.json') {
                return Received(
                  const HttpResponse(
                    status: 200,
                    body: '{"version":1,"catalogHosts":["good.example.com"]}',
                  ),
                );
              }
              return Received(const HttpResponse(status: 404, body: ''));
            });

        // Act
        final RescueOutcome outcome = await _router(
          transport,
          hosts: <String>[
            'https://broken.example.com',
            'https://good.example.com',
          ],
        ).rescue(_core);

        // Assert
        expect(outcome, isA<RescueUnavailable>());

        expect(
          transport.sent.map((Uri u) => u.host),
          containsAllInOrder(<String>[
            'broken.example.com',
            'good.example.com',
          ]),
        );
      },
    );
  });
}
