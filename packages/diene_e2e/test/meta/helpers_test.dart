import 'dart:convert';
import 'dart:io';

import 'package:diene_e2e/test_helper.dart';
import 'package:flutter_test/flutter_test.dart';

JourneyResult _result(List<(String, bool, String?)> steps) =>
    JourneyResult(<JourneyStepResult>[
      for (final (String name, bool ok, String? detail) in steps)
        JourneyStepResult(name: name, ok: ok, detail: detail),
    ]);

void main() {
  group('expectJourneyOk', () {
    test('passes on a journey whose steps all passed', () {
      // Arrange
      final JourneyResult result = _result(<(String, bool, String?)>[
        ('a', true, null),
        ('b', true, null),
      ]);

      // Act
      void check() => expectJourneyOk(result);

      // Assert
      expect(check, returnsNormally);
    });

    test('fails naming the failing step and its detail', () {
      // Arrange
      final JourneyResult result = _result(<(String, bool, String?)>[
        ('a', true, null),
        ('redeem', false, 'boom'),
      ]);

      // Act
      void check() => expectJourneyOk(result);

      // Assert
      expect(
        check,
        throwsA(
          isA<JourneyAssertionError>().having(
            (JourneyAssertionError e) => e.toString(),
            'toString',
            "JourneyAssertionError: expected journey to pass, but failed at step 'redeem' — boom",
          ),
        ),
      );
    });

    test('fails naming the step when there is no detail', () {
      // Arrange
      final JourneyResult result = _result(<(String, bool, String?)>[
        ('redeem', false, null),
      ]);

      // Act
      void check() => expectJourneyOk(result);

      // Assert
      expect(
        check,
        throwsA(
          isA<JourneyAssertionError>().having(
            (JourneyAssertionError e) => e.message,
            'message',
            "expected journey to pass, but failed at step 'redeem'",
          ),
        ),
      );
    });
  });

  group('expectJourneyFailedAt', () {
    test('passes when the named step is the first failure', () {
      // Arrange
      final JourneyResult result = _result(<(String, bool, String?)>[
        ('a', true, null),
        ('b', false, null),
      ]);

      // Act
      void check() => expectJourneyFailedAt(result, 'b');

      // Assert
      expect(check, returnsNormally);
    });

    test('fails when the journey passed', () {
      // Arrange
      final JourneyResult result = _result(<(String, bool, String?)>[
        ('a', true, null),
      ]);

      // Act
      void check() => expectJourneyFailedAt(result, 'a');

      // Assert
      expect(
        check,
        throwsA(
          isA<JourneyAssertionError>().having(
            (JourneyAssertionError e) => e.message,
            'message',
            "expected journey to fail at 'a', but it passed",
          ),
        ),
      );
    });

    test('fails when another step failed', () {
      // Arrange
      final JourneyResult result = _result(<(String, bool, String?)>[
        ('a', false, null),
      ]);

      // Act
      void check() => expectJourneyFailedAt(result, 'b');

      // Assert
      expect(
        check,
        throwsA(
          isA<JourneyAssertionError>().having(
            (JourneyAssertionError e) => e.message,
            'message',
            "expected journey to fail at 'b', but it failed at 'a'",
          ),
        ),
      );
    });
  });

  group('expectEquals and expectTrue', () {
    test('pass on equal values and a true condition', () {
      // Arrange
      const int value = 3;

      // Act
      void check() {
        expectEquals(value, 3);
        expectEquals<String?>(null, null, reason: 'both absent');
        expectTrue(value > 2, 'unused');
      }

      // Assert
      expect(check, returnsNormally);
    });

    test('expectEquals fails with both values and the reason', () {
      // Arrange
      const int value = 3;

      // Act
      void withReason() => expectEquals(value, 4, reason: 'count');
      void withoutReason() => expectEquals(value, 4);

      // Assert
      expect(
        withReason,
        throwsA(
          isA<JourneyAssertionError>().having(
            (JourneyAssertionError e) => e.message,
            'message',
            'expected <4> but got <3> (count)',
          ),
        ),
      );
      expect(
        withoutReason,
        throwsA(
          isA<JourneyAssertionError>().having(
            (JourneyAssertionError e) => e.message,
            'message',
            'expected <4> but got <3>',
          ),
        ),
      );
    });

    test('expectTrue fails with the message', () {
      // Arrange
      const bool condition = false;

      // Act
      void check() => expectTrue(condition, 'must hold');

      // Assert
      expect(
        check,
        throwsA(
          isA<JourneyAssertionError>().having(
            (JourneyAssertionError e) => e.message,
            'message',
            'must hold',
          ),
        ),
      );
    });
  });

  group('Journey', () {
    test('runs every step in order when all pass', () async {
      // Arrange
      final List<String> ran = <String>[];
      final Journey journey = Journey('j', <JourneyStep>[
        JourneyStep('a', () async => (ran..add('a')).isNotEmpty),
        JourneyStep('b', () async => (ran..add('b')).isNotEmpty),
      ]);

      // Act
      final JourneyResult result = await journey.run();

      // Assert
      expect(journey.name, 'j');
      expect(ran, <String>['a', 'b']);
      expect(result.ok, isTrue);
      expect(result.firstFailure, isNull);
      expect(result.steps.map((JourneyStepResult s) => s.name), <String>[
        'a',
        'b',
      ]);
    });

    test('stops at the first failing step and records no later step', () async {
      // Arrange
      final List<String> ran = <String>[];
      final Journey journey = Journey('j', <JourneyStep>[
        JourneyStep('a', () async => false),
        JourneyStep('b', () async => (ran..add('b')).isNotEmpty),
      ]);

      // Act
      final JourneyResult result = await journey.run();

      // Assert
      expect(ran, isEmpty);
      expect(result.ok, isFalse);
      expect(result.steps, hasLength(1));
      expect(result.firstFailure!.name, 'a');
      expect(result.firstFailure!.detail, isNull);
    });

    test('a throwing step is a failure carrying the error text', () async {
      // Arrange
      final Journey journey = Journey('j', <JourneyStep>[
        JourneyStep('a', () async => throw StateError('broken')),
      ]);

      // Act
      final JourneyResult result = await journey.run();

      // Assert
      expect(result.ok, isFalse);
      expect(result.firstFailure!.ok, isFalse);
      expect(result.firstFailure!.detail, 'Bad state: broken');
    });

    test('an empty journey passes', () async {
      // Arrange
      final Journey journey = Journey('empty', const <JourneyStep>[]);

      // Act
      final JourneyResult result = await journey.run();

      // Assert
      expect(result.ok, isTrue);
      expect(result.steps, isEmpty);
    });
  });

  group('StubServer', () {
    late StubServer server;
    late HttpClient client;

    setUp(() async {
      server = await StubServer.start();
      client = HttpClient();
    });

    tearDown(() async {
      client.close(force: true);
      await server.close();
    });

    Future<HttpClientResponse> send(
      String method,
      String path,
      String body,
    ) async {
      final HttpClientRequest request = await client.openUrl(
        method,
        Uri.parse('${server.baseUrl}$path'),
      );
      request.headers.set('x-trace', 'one');
      request.write(body);
      return request.close();
    }

    test('routes to a handler and records the request', () async {
      // Arrange
      server.on(
        'post',
        '/echo',
        (StubRequest r) => StubResponse.json(
          r.jsonBody(),
          status: 201,
          headers: <String, String>{'x-extra': 'yes'},
        ),
      );

      // Act
      final HttpClientResponse response = await send(
        'POST',
        '/echo',
        '{"a":1}',
      );
      final String body = await utf8.decoder.bind(response).join();

      // Assert
      expect(server.baseUrl, startsWith('http://127.0.0.1:'));
      expect(response.statusCode, 201);
      expect(response.headers.value('content-type'), 'application/json');
      expect(response.headers.value('cache-control'), 'no-store');
      expect(response.headers.value('x-extra'), 'yes');
      expect(jsonDecode(body), <String, Object?>{'a': 1});
      final StubRequest recorded = server.requests.single;
      expect(recorded.method, 'POST');
      expect(recorded.path, '/echo');
      expect(recorded.headers['x-trace'], 'one');
      expect(recorded.body, '{"a":1}');
    });

    test('a plain response sends its status, headers and body', () async {
      // Arrange
      server.on(
        'GET',
        '/text',
        (StubRequest r) => const StubResponse(
          status: 202,
          body: 'hi',
          headers: <String, String>{'x-kind': 'text'},
        ),
      );
      server.on('GET', '/empty', (StubRequest r) => const StubResponse());

      // Act
      final HttpClientResponse text = await send('GET', '/text', '');
      final String textBody = await utf8.decoder.bind(text).join();
      final HttpClientResponse empty = await send('GET', '/empty', '');
      final String emptyBody = await utf8.decoder.bind(empty).join();

      // Assert
      expect(text.statusCode, 202);
      expect(text.headers.value('x-kind'), 'text');
      expect(textBody, 'hi');
      expect(empty.statusCode, 200);
      expect(emptyBody, isEmpty);
    });

    test('an unregistered route is 404 and still recorded', () async {
      // Arrange
      server.on('POST', '/known', (StubRequest r) => const StubResponse());

      // Act
      final HttpClientResponse wrongPath = await send('POST', '/nope', '');
      await wrongPath.drain<void>();
      final HttpClientResponse wrongMethod = await send('GET', '/known', '');
      await wrongMethod.drain<void>();

      // Assert
      expect(wrongPath.statusCode, 404);
      expect(wrongMethod.statusCode, 404);
      expect(server.requests.map((StubRequest r) => r.path), <String>[
        '/nope',
        '/known',
      ]);
    });

    test(
      'a later handler for the same route replaces the earlier one',
      () async {
        // Arrange
        server.on(
          'GET',
          '/x',
          (StubRequest r) => const StubResponse(status: 201),
        );
        server.on(
          'GET',
          '/x',
          (StubRequest r) => const StubResponse(status: 202),
        );

        // Act
        final HttpClientResponse response = await send('GET', '/x', '');
        await response.drain<void>();

        // Assert
        expect(response.statusCode, 202);
        expect(server.handlerFor('get', '/x'), isNotNull);
        expect(server.handlerFor('GET', '/y'), isNull);
      },
    );

    test('jsonBody refuses a body that is not a JSON object', () {
      // Arrange
      StubRequest request(String body) =>
          StubRequest(method: 'POST', path: '/', headers: const {}, body: body);

      // Act
      final Map<String, Object?> good = request('{"ok":true}').jsonBody();

      // Assert
      expect(good, <String, Object?>{'ok': true});
      for (final String bad in <String>['', '[1,2]', '"text"', '3', 'null']) {
        expect(
          () => request(bad).jsonBody(),
          throwsA(isA<FormatException>()),
          reason: bad,
        );
      }
      expect(() => request('{').jsonBody(), throwsA(isA<FormatException>()));
    });

    test('clearRequests empties the log and keeps the handlers', () async {
      // Arrange
      server.on('POST', '/x', (StubRequest r) => const StubResponse());
      await (await send('POST', '/x', '')).drain<void>();

      // Act
      server.clearRequests();
      final List<StubRequest> cleared = server.requests;
      final HttpClientResponse again = await send('POST', '/x', '');
      await again.drain<void>();

      // Assert
      expect(cleared, isEmpty);
      expect(again.statusCode, 200);
      expect(server.requests, hasLength(1));
      expect(() => server.requests.clear(), throwsUnsupportedError);
    });
  });
}
