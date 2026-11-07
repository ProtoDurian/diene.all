import 'dart:convert';

import 'package:diene_api_engine/diene_api_engine.dart';
import 'package:diene_api_engine/test_helper.dart';
import 'package:flutter_test/flutter_test.dart';

final ResourceKey _keyA = ResourceKey(
  platform: 'lithium',
  landscape: 'lapras',
  service: 'api',
  resourceName: 'a',
);
final ResourceKey _keyB = ResourceKey(
  platform: 'lithium',
  landscape: 'lapras',
  service: 'api',
  resourceName: 'b',
);

HttpRequest _get(String url) =>
    HttpRequest(method: HttpMethod.get, url: Uri.parse(url));

Matcher _assertion(String text) => throwsA(
  isA<AssertionError>().having(
    (AssertionError e) => e.message.toString(),
    'message',
    contains(text),
  ),
);

void main() {
  final Problem problem = problemFixture(type: 'urn:test:a', status: 409);

  group('expectOk', () {
    test('returns the value of an Ok', () {
      // Arrange
      const Result<int> result = Ok<int>(7);

      // Act
      final int value = expectOk(result);

      // Assert
      expect(value, 7);
    });

    test('throws on an Err, naming its type and status', () {
      // Arrange
      final Result<int> result = Err<int>(problem);

      // Act
      int act() => expectOk(result);

      // Assert
      expect(act, _assertion('expected Ok but got Err(urn:test:a, 409)'));
    });

    test('appends the reason', () {
      // Arrange
      final Result<int> result = Err<int>(problem);

      // Act
      int act() => expectOk(result, because: 'login');

      // Assert
      expect(act, _assertion(' — login'));
    });
  });

  group('expectErr', () {
    test('returns the problem of an Err', () {
      // Arrange
      final Result<int> result = Err<int>(problem);

      // Act
      final Problem got = expectErr(result);

      // Assert
      expect(got, problem);
    });

    test('throws on an Ok, showing its value', () {
      // Arrange
      const Result<int> result = Ok<int>(7);

      // Act
      Problem act() => expectErr(result);

      // Assert
      expect(act, _assertion('expected Err but got Ok(7)'));
    });

    test('appends the reason', () {
      // Arrange
      const Result<int> result = Ok<int>(7);

      // Act
      Problem act() => expectErr(result, because: 'denied');

      // Assert
      expect(act, _assertion('Ok(7) — denied'));
    });
  });

  group('expectProblemType', () {
    test('returns a problem of the expected type', () {
      // Arrange
      final Result<int> result = Err<int>(problem);

      // Act
      final Problem got = expectProblemType(result, 'urn:test:a');

      // Assert
      expect(got.status, 409);
    });

    test('throws on another type', () {
      // Arrange
      final Result<int> result = Err<int>(problem);

      // Act
      Problem act() => expectProblemType(result, 'urn:test:b');

      // Assert
      expect(act, _assertion('expected problem type "urn:test:b"'));
    });

    test('throws on an Ok', () {
      // Arrange
      const Result<int> result = Ok<int>(1);

      // Act
      Problem act() => expectProblemType(result, 'urn:test:a');

      // Assert
      expect(act, throwsA(isA<AssertionError>()));
    });
  });

  group('check', () {
    test('passes when true', () {
      // Arrange
      const bool condition = true;

      // Act
      void act() => check(condition, 'never');

      // Assert
      expect(act, returnsNormally);
    });

    test('throws its message when false', () {
      // Arrange
      const bool condition = false;

      // Act
      void act() => check(condition, 'it broke');

      // Assert
      expect(act, _assertion('it broke'));
    });
  });

  group('builders', () {
    test('problemFixture round-trips through Problem.fromJson', () {
      // Arrange
      final Problem built = problemFixture(
        detail: 'd',
        recoverable: true,
        data: <String, Object?>{'k': 1},
      );

      // Act
      final Problem parsed = Problem.fromJson(built.toJson());

      // Assert
      expect(parsed, built);
      expect(built.type, 'urn:diene:problem:test');
      expect(built.status, 400);
    });

    test('problemResponse is a problem body at the problem status', () {
      // Arrange
      final Received outcome = problemResponse(problem);

      // Act
      final Object? body = jsonDecode(outcome.response.body);

      // Assert
      expect(outcome.response.status, 409);
      expect(isProblemJson(body), isTrue);
      expect(Problem.fromJson(body! as Map<String, Object?>), problem);
    });

    test('okJson is a 2xx JSON object', () {
      // Arrange
      final Received outcome = okJson(<String, Object?>{'a': 1}, status: 201);

      // Act
      final Map<String, Object?>? body = tryDecodeObject(outcome.response.body);

      // Assert
      expect(outcome.response.status, 201);
      expect(body, <String, Object?>{'a': 1});
      expect(outcome.response.headers['content-type'], 'application/json');
    });

    test('nonProblemJson is JSON that is not a problem', () {
      // Arrange
      final Received outcome = nonProblemJson(<String, Object?>{'error': 'x'});

      // Act
      final Map<String, Object?>? body = tryDecodeObject(outcome.response.body);

      // Assert
      expect(outcome.response.status, 400);
      expect(body, isNotNull);
      expect(isProblemJson(body), isFalse);
    });

    test('nonJsonResponse is not JSON', () {
      // Arrange
      final Received outcome = nonJsonResponse();

      // Act
      final Map<String, Object?>? body = tryDecodeObject(outcome.response.body);

      // Assert
      expect(outcome.response.status, 502);
      expect(body, isNull);
    });

    test('networkFailure carries its reason', () {
      // Arrange
      const String reason = 'dns';

      // Act
      final NetworkFailure outcome = networkFailure(reason);

      // Assert
      expect(outcome.reason, reason);
      expect(networkFailure().reason, 'connection refused');
    });
  });

  group('FakeHttpTransport', () {
    test('records every request and answers from its responder', () async {
      // Arrange
      final FakeHttpTransport transport = FakeHttpTransport(
        (HttpRequest request) =>
            okJson(<String, Object?>{'p': request.url.path}),
      );

      // Act
      final TransportOutcome outcome = await transport.send(
        _get('https://a/x'),
      );
      await transport.send(_get('https://a/y'));

      // Assert
      expect((outcome as Received).response.body, '{"p":"/x"}');
      expect(transport.callCount, 2);
      expect(transport.sent.map((HttpRequest r) => r.url.path), <String>[
        '/x',
        '/y',
      ]);
    });

    test('sequence replays in order and repeats the last', () async {
      // Arrange
      final FakeHttpTransport transport = FakeHttpTransport.sequence(
        <TransportOutcome>[
          networkFailure('first'),
          okJson(<String, Object?>{}),
        ],
      );

      // Act
      final List<TransportOutcome> outcomes = <TransportOutcome>[
        for (int i = 0; i < 3; i++) await transport.send(_get('https://a/')),
      ];

      // Assert
      expect(outcomes[0], isA<NetworkFailure>());
      expect(outcomes[1], isA<Received>());
      expect(outcomes[2], same(outcomes[1]));
    });

    test('byHost routes on host and falls back to orElse', () async {
      // Arrange
      final Received ok = okJson(<String, Object?>{});
      final FakeHttpTransport transport = FakeHttpTransport.byHost(
        <String, TransportOutcome>{'a.test': ok},
      );
      final FakeHttpTransport custom = FakeHttpTransport.byHost(
        const <String, TransportOutcome>{},
        orElse: networkFailure('custom'),
      );

      // Act
      final TransportOutcome hit = await transport.send(
        _get('https://a.test/'),
      );
      final TransportOutcome miss = await transport.send(
        _get('https://b.test/'),
      );
      final TransportOutcome other = await custom.send(_get('https://b.test/'));

      // Assert
      expect(hit, same(ok));
      expect((miss as NetworkFailure).reason, 'unmapped host');
      expect((other as NetworkFailure).reason, 'custom');
    });
  });

  group('HangingTransport', () {
    test('records the request and never answers', () async {
      // Arrange
      final HangingTransport transport = HangingTransport();

      // Act
      final Future<TransportOutcome> pending = transport.send(
        _get('https://a/'),
      );
      final Object? first = await Future.any(<Future<Object?>>[
        pending,
        Future<Object?>.delayed(const Duration(milliseconds: 20), () => 'late'),
      ]);

      // Assert
      expect(first, 'late');
      expect(transport.sent.single.url.host, 'a');
    });
  });

  group('FakeAuth', () {
    test('returns only the token of the asked resource', () async {
      // Arrange
      final FakeAuth auth = FakeAuth(<String, String>{
        _keyA.mapKey: 'tok-a',
        _keyB.mapKey: 'tok-b',
      }, expiresAt: DateTime.utc(2030));

      // Act
      final ResourceToken a = expectOk(await auth.tokenFor(_keyA));
      final ResourceToken b = expectOk(await auth.tokenFor(_keyB));

      // Assert
      expect(a.token, 'tok-a');
      expect(b.token, 'tok-b');
      expect(a.expiresAt, DateTime.utc(2030));
      expect(auth.queried, <String>[_keyA.mapKey, _keyB.mapKey]);
    });

    test('an unknown resource fails closed with a 401', () async {
      // Arrange
      final FakeAuth auth = FakeAuth(const <String, String>{});

      // Act
      final Result<ResourceToken> result = await auth.tokenFor(_keyA);

      // Assert
      final Problem got = expectErr(result);
      expect(got.status, 401);
      expect(got.detail, _keyA.mapKey);
    });

    test('fetchAllTokens resolves each key on its own', () async {
      // Arrange
      final FakeAuth auth = FakeAuth(<String, String>{_keyA.mapKey: 'tok-a'});

      // Act
      final Map<ResourceKey, Result<ResourceToken>> all = await auth
          .fetchAllTokens(<ResourceKey>[_keyA, _keyB]);

      // Assert
      expect(expectOk(all[_keyA]!).token, 'tok-a');
      expect(expectErr(all[_keyB]!).status, 401);
      expect(expectOk(all[_keyA]!).expiresAt, DateTime.utc(2999));
    });

    test('invalidate and invalidateAll keep the tokens', () async {
      // Arrange
      final FakeAuth auth = FakeAuth(<String, String>{_keyA.mapKey: 'tok-a'});

      // Act
      auth
        ..invalidate(_keyA)
        ..invalidateAll();

      // Assert
      expect(expectOk(await auth.tokenFor(_keyA)).token, 'tok-a');
    });
  });

  group('FakeRescueStore', () {
    test('stores what it logs and reads its seed', () async {
      // Arrange
      final FakeRescueStore store = FakeRescueStore(<String, String>{'s': '1'});

      // Act
      await store.write('k', 'v');
      await store.delete('s');

      // Assert
      expect(await store.read('k'), 'v');
      expect(await store.read('s'), isNull);
      expect(store.writes, <String>['k']);
    });
  });

  group('timing helpers', () {
    test('noJitter is zero and noSleep returns at once', () async {
      // Arrange
      final Stopwatch watch = Stopwatch()..start();

      // Act
      await noSleep(const Duration(hours: 1));

      // Assert
      expect(noJitter(), Duration.zero);
      expect(watch.elapsed, lessThan(const Duration(seconds: 1)));
    });

    test('FakeClock advances by hand and by sleep', () async {
      // Arrange
      final FakeClock clock = FakeClock(5);

      // Act
      clock.advance(const Duration(milliseconds: 10));
      await clock.sleep(const Duration(milliseconds: 20));

      // Assert
      expect(clock.nowMs(), 35);
      expect(FakeClock().nowMs(), 0);
    });
  });
}
