/// Fakes, builders and plain-throw assertions; no test framework needed.
library;

import 'dart:async';
import 'dart:convert';

import 'package:diene_auth_engine/diene_auth_engine.dart'
    show IAuth, ResourceKey, ResourceToken;
import 'package:diene_problems/diene_problems.dart' show Problem;
import 'package:diene_result/diene_result.dart';

import 'src/rescue/store.dart';
import 'src/transport.dart';

/// Returns the value of an [Ok]; throws [AssertionError] on an [Err].
T expectOk<T>(Result<T> result, {String? because}) => switch (result) {
  Ok<T>(:final value) => value,
  Err<T>(:final problem) => throw AssertionError(
    'expected Ok but got Err(${problem.type}, ${problem.status})'
    '${because == null ? '' : ' — $because'}',
  ),
};

/// Returns the problem of an [Err]; throws [AssertionError] on an [Ok].
Problem expectErr<T>(Result<T> result, {String? because}) => switch (result) {
  Ok<T>(:final value) => throw AssertionError(
    'expected Err but got Ok($value)${because == null ? '' : ' — $because'}',
  ),
  Err<T>(:final problem) => problem,
};

/// Returns the problem of an [Err] of [type]; throws otherwise.
Problem expectProblemType<T>(Result<T> result, String type) {
  final Problem problem = expectErr(result);
  if (problem.type != type) {
    throw AssertionError(
      'expected problem type "$type" but got "${problem.type}"',
    );
  }
  return problem;
}

/// Throws [AssertionError] with [message] when [condition] is false.
void check(bool condition, String message) {
  if (!condition) {
    throw AssertionError(message);
  }
}

/// A valid problem.
Problem problemFixture({
  String type = 'urn:diene:problem:test',
  String title = 'Test problem',
  int status = 400,
  String? detail,
  bool recoverable = false,
  Map<String, Object?> data = const <String, Object?>{},
}) => Problem(
  type: type,
  title: title,
  status: status,
  detail: detail,
  recoverable: recoverable,
  data: data,
);

/// A 2xx JSON response.
Received okJson(Map<String, Object?> body, {int status = 200}) => Received(
  HttpResponse(
    status: status,
    headers: const <String, String>{'content-type': 'application/json'},
    body: jsonEncode(body),
  ),
);

/// A non-2xx response whose body is [problem].
Received problemResponse(Problem problem) => Received(
  HttpResponse(
    status: problem.status,
    headers: const <String, String>{'content-type': 'application/json'},
    body: jsonEncode(problem.toJson()),
  ),
);

/// A non-2xx JSON body that is not a problem.
Received nonProblemJson(Map<String, Object?> body, {int status = 400}) =>
    Received(
      HttpResponse(
        status: status,
        headers: const <String, String>{'content-type': 'application/json'},
        body: jsonEncode(body),
      ),
    );

/// A non-JSON error response.
Received nonJsonResponse({int status = 502, String body = 'Bad Gateway'}) =>
    Received(HttpResponse(status: status, body: body));

/// An opaque network failure.
NetworkFailure networkFailure([String reason = 'connection refused']) =>
    NetworkFailure(reason);

/// A scripted [HttpTransport] that records every request.
class FakeHttpTransport implements HttpTransport {
  FakeHttpTransport(this._responder);

  /// Outcomes in order, one per call; the last one repeats.
  factory FakeHttpTransport.sequence(List<TransportOutcome> outcomes) {
    var index = 0;
    return FakeHttpTransport((HttpRequest _) {
      final TransportOutcome outcome =
          outcomes[index < outcomes.length ? index : outcomes.length - 1];
      index++;
      return outcome;
    });
  }

  /// Outcomes by request host, else [orElse].
  factory FakeHttpTransport.byHost(
    Map<String, TransportOutcome> byHost, {
    TransportOutcome orElse = const NetworkFailure('unmapped host'),
  }) => FakeHttpTransport(
    (HttpRequest request) => byHost[request.url.host] ?? orElse,
  );

  final TransportOutcome Function(HttpRequest request) _responder;

  /// Every request handled, in order.
  final List<HttpRequest> sent = <HttpRequest>[];

  int get callCount => sent.length;

  @override
  Future<TransportOutcome> send(HttpRequest request) async {
    sent.add(request);
    return _responder(request);
  }
}

/// A transport whose sends never complete.
class HangingTransport implements HttpTransport {
  final List<HttpRequest> sent = <HttpRequest>[];

  @override
  Future<TransportOutcome> send(HttpRequest request) {
    sent.add(request);
    return Completer<TransportOutcome>().future;
  }
}

/// A fake [IAuth]: tokens by [ResourceKey.mapKey]; an unknown key is an [Err].
class FakeAuth implements IAuth {
  FakeAuth(this._tokens, {DateTime? expiresAt})
    : _expiresAt = expiresAt ?? DateTime.utc(2999);

  final Map<String, String> _tokens;
  final DateTime _expiresAt;

  /// Map keys asked for, in order.
  final List<String> queried = <String>[];

  @override
  Future<Result<ResourceToken>> tokenFor(ResourceKey key) async {
    queried.add(key.mapKey);
    final String? token = _tokens[key.mapKey];
    if (token == null) {
      return Err<ResourceToken>(
        Problem(
          type: 'urn:diene:test:no-token',
          title: 'No token',
          status: 401,
          detail: key.mapKey,
        ),
      );
    }
    return Ok<ResourceToken>(
      ResourceToken(token: token, expiresAt: _expiresAt),
    );
  }

  @override
  Future<Map<ResourceKey, Result<ResourceToken>>> fetchAllTokens(
    Iterable<ResourceKey> keys,
  ) async {
    final Map<ResourceKey, Result<ResourceToken>> out =
        <ResourceKey, Result<ResourceToken>>{};
    for (final ResourceKey key in keys) {
      out[key] = await tokenFor(key);
    }
    return out;
  }

  @override
  void invalidateAll() {}

  @override
  void invalidate(ResourceKey key) {}
}

/// An in-memory rescue store that logs the keys it writes.
class FakeRescueStore extends InMemoryRescueStore {
  FakeRescueStore([super.seed]);

  final List<String> writes = <String>[];

  @override
  Future<void> write(String key, String value) async {
    writes.add(key);
    return super.write(key, value);
  }
}

/// Zero jitter, for a deterministic scan order.
Duration noJitter() => Duration.zero;

/// A sleep that returns at once.
Future<void> noSleep(Duration duration) async {}

/// A fake millisecond clock, advanced by hand or by [sleep].
class FakeClock {
  FakeClock([this._ms = 0]);

  int _ms;

  int nowMs() => _ms;

  void advance(Duration by) => _ms += by.inMilliseconds;

  /// A sleep that advances this clock and returns at once.
  Future<void> sleep(Duration duration) async => advance(duration);
}
