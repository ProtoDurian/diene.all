/// The Dart family test harness: the member TestHelpers plus stub servers,
/// journey drivers, the app-handoff fixture and plain-throw assertions.
///
/// No test framework is needed. `expectOk`/`expectErr` are `diene_result`'s
/// and `FakeAuth` is `diene_auth_engine`'s; import
/// `package:diene_api_engine/test_helper.dart` with a prefix for its variants.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'src/app_handoff/carrier.dart';
import 'src/app_handoff/wire.dart';

export 'package:diene_api_engine/test_helper.dart'
    hide FakeAuth, expectErr, expectOk;
export 'package:diene_auth_engine/test_helper.dart';
export 'package:diene_config/test_helper.dart';
export 'package:diene_interfaces/test_helper.dart';
export 'package:diene_problems/test_helper.dart';
export 'package:diene_result/test_helper.dart';

/// Thrown by an assertion helper when a check fails.
class JourneyAssertionError extends Error {
  JourneyAssertionError(this.message);

  final String message;

  @override
  String toString() => 'JourneyAssertionError: $message';
}

/// Asserts the whole [result] succeeded, reporting the first failing step.
void expectJourneyOk(JourneyResult result) {
  if (result.ok) return;
  final JourneyStepResult? failure = result.firstFailure;
  final String where = failure == null
      ? 'unknown step'
      : "step '${failure.name}'${failure.detail == null ? '' : ' — ${failure.detail}'}";
  throw JourneyAssertionError('expected journey to pass, but failed at $where');
}

/// Asserts the journey failed at the step named [stepName].
void expectJourneyFailedAt(JourneyResult result, String stepName) {
  final JourneyStepResult? failure = result.firstFailure;
  if (failure == null) {
    throw JourneyAssertionError(
      "expected journey to fail at '$stepName', but it passed",
    );
  }
  if (failure.name != stepName) {
    throw JourneyAssertionError(
      "expected journey to fail at '$stepName', but it failed at '${failure.name}'",
    );
  }
}

/// Asserts [actual] equals [expected], with an optional [reason] for context.
void expectEquals<T>(T actual, T expected, {String? reason}) {
  if (actual == expected) return;
  final String suffix = reason == null ? '' : ' ($reason)';
  throw JourneyAssertionError('expected <$expected> but got <$actual>$suffix');
}

/// Asserts [condition] holds, throwing with [message] otherwise.
void expectTrue(bool condition, String message) {
  if (!condition) throw JourneyAssertionError(message);
}

/// The outcome of running one [JourneyStep].
class JourneyStepResult {
  const JourneyStepResult({required this.name, required this.ok, this.detail});

  final String name;
  final bool ok;
  final String? detail;
}

/// One named step in a journey. Returns `true` when the step succeeded.
class JourneyStep {
  const JourneyStep(this.name, this.run);

  final String name;
  final Future<bool> Function() run;
}

/// The result of running a whole [Journey].
class JourneyResult {
  const JourneyResult(this.steps);

  final List<JourneyStepResult> steps;

  /// Whether every step succeeded.
  bool get ok => steps.every((JourneyStepResult s) => s.ok);

  /// The first failing step, or `null` when the journey passed.
  JourneyStepResult? get firstFailure {
    for (final JourneyStepResult s in steps) {
      if (!s.ok) return s;
    }
    return null;
  }
}

/// An ordered set of steps, run in sequence. A step that returns `false` or
/// throws fails the journey, and later steps are not run or recorded.
class Journey {
  Journey(this.name, this.steps);

  final String name;
  final List<JourneyStep> steps;

  Future<JourneyResult> run() async {
    final List<JourneyStepResult> results = <JourneyStepResult>[];
    for (final JourneyStep step in steps) {
      bool ok;
      String? detail;
      try {
        ok = await step.run();
      } on Object catch (error) {
        ok = false;
        detail = error.toString();
      }
      results.add(JourneyStepResult(name: step.name, ok: ok, detail: detail));
      if (!ok) break;
    }
    return JourneyResult(results);
  }
}

/// What a deferred-login journey attempt resolved to.
enum DeferredLoginJourneyOutcome {
  /// A valid carrier was redeemed into a one-time token.
  redeemed,

  /// No usable carrier, or the redeem failed: fall back to interactive login.
  interactiveFallback,
}

/// The result of driving one deferred-login attempt.
class DeferredLoginResult {
  const DeferredLoginResult({required this.outcome, this.redeem});

  final DeferredLoginJourneyOutcome outcome;

  /// Present only when [outcome] is [DeferredLoginJourneyOutcome.redeemed].
  final AppHandoffRedeemResponse? redeem;
}

/// Client-side driver for the deferred-login flow against [baseUrl], for
/// example a running [StubServer]'s base URL.
class DeferredLoginJourney {
  DeferredLoginJourney({
    required this.baseUrl,
    this.mountPath = appHandoffDefaultMount,
    required this.platform,
    HttpClient? httpClient,
  }) : _client = httpClient ?? HttpClient();

  final String baseUrl;
  final String mountPath;

  /// `android` or `ios`: the redeem `device.platform` field. `android` reads
  /// the carrier as an Install Referrer, anything else as clipboard text.
  final String platform;

  final HttpClient _client;

  /// Runs the client flow for a captured [carrier] (the raw Install Referrer
  /// or clipboard text): an absent or invalid carrier, or a failed redeem,
  /// gives [DeferredLoginJourneyOutcome.interactiveFallback].
  Future<DeferredLoginResult> redeemCarrier(String? carrier) async {
    final String? nonce = platform == 'android'
        ? parseAppHandoffInstallReferrer(carrier)
        : parseAppHandoffClipboard(carrier);
    if (nonce == null) {
      return const DeferredLoginResult(
        outcome: DeferredLoginJourneyOutcome.interactiveFallback,
      );
    }
    return redeemNonce(nonce);
  }

  /// Redeems an already-parsed [nonce] directly.
  Future<DeferredLoginResult> redeemNonce(String nonce) async {
    final AppHandoffRedeemRequest body = AppHandoffRedeemRequest(
      nonce: nonce,
      device: AppHandoffDevice(platform: platform),
    );
    final HttpClientRequest request = await _client.postUrl(
      Uri.parse('$baseUrl$mountPath/$appHandoffRedeemPath'),
    );
    request.headers.contentType = ContentType.json;
    request.write(jsonEncode(body.toJson()));
    final HttpClientResponse response = await request.close();
    final String responseBody = await utf8.decoder.bind(response).join();

    if (response.statusCode != 200) {
      return const DeferredLoginResult(
        outcome: DeferredLoginJourneyOutcome.interactiveFallback,
      );
    }
    final Map<String, Object?> json = (jsonDecode(responseBody) as Map).map(
      (Object? k, Object? v) => MapEntry(k.toString(), v),
    );
    return DeferredLoginResult(
      outcome: DeferredLoginJourneyOutcome.redeemed,
      redeem: AppHandoffRedeemResponse.fromJson(json),
    );
  }

  /// Releases the underlying HTTP client.
  void close() => _client.close(force: true);
}

/// A recorded inbound request.
class StubRequest {
  StubRequest({
    required this.method,
    required this.path,
    required this.headers,
    required this.body,
  });

  final String method;
  final String path;
  final Map<String, String> headers;
  final String body;

  /// Decodes [body] as a JSON object; throws [FormatException] otherwise.
  Map<String, Object?> jsonBody() {
    final Object? decoded = body.isEmpty ? null : jsonDecode(body);
    if (decoded is! Map) {
      throw FormatException('request body is not a JSON object', body);
    }
    return decoded.map((Object? k, Object? v) => MapEntry(k.toString(), v));
  }
}

/// A canned response a handler returns for a matched route.
class StubResponse {
  const StubResponse({
    this.status = 200,
    this.body = '',
    this.headers = const <String, String>{},
  });

  /// A JSON response with `Content-Type: application/json` and
  /// `Cache-Control: no-store`.
  factory StubResponse.json(
    Object? value, {
    int status = 200,
    Map<String, String> headers = const <String, String>{},
  }) => StubResponse(
    status: status,
    body: jsonEncode(value),
    headers: <String, String>{
      'content-type': 'application/json',
      'cache-control': 'no-store',
      ...headers,
    },
  );

  final int status;
  final String body;
  final Map<String, String> headers;
}

/// A route handler: receives the recorded request and returns the response.
typedef StubHandler = FutureOr<StubResponse> Function(StubRequest request);

/// An in-process loopback HTTP server. Register handlers by `METHOD /path`,
/// then point a client at [baseUrl]. Every request is recorded in [requests].
class StubServer {
  StubServer._(this._server)
    : baseUrl = 'http://${_server.address.host}:${_server.port}';

  final HttpServer _server;

  /// The base URL a client should target, e.g. `http://127.0.0.1:54321`.
  final String baseUrl;

  final Map<String, StubHandler> _routes = <String, StubHandler>{};
  final List<StubRequest> _requests = <StubRequest>[];

  /// Every request the server has received, in arrival order.
  List<StubRequest> get requests => List<StubRequest>.unmodifiable(_requests);

  /// Binds a stub server on an ephemeral loopback port and starts serving.
  static Future<StubServer> start() async {
    final HttpServer server = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    final StubServer stub = StubServer._(server);
    unawaited(stub._serve());
    return stub;
  }

  /// Registers [handler] for `method path`, replacing any earlier one.
  void on(String method, String path, StubHandler handler) {
    _routes[_key(method, path)] = handler;
  }

  /// The handler registered for `method path`, or `null`.
  ///
  /// Call a handler directly to see what it throws: over HTTP a throwing
  /// handler is not answered.
  StubHandler? handlerFor(String method, String path) =>
      _routes[_key(method, path)];

  /// Clears the recorded request log; route handlers are kept.
  void clearRequests() => _requests.clear();

  /// Stops the server, releasing its port.
  Future<void> close() => _server.close(force: true);

  Future<void> _serve() async {
    await for (final HttpRequest request in _server) {
      await _handle(request);
    }
  }

  Future<void> _handle(HttpRequest request) async {
    final String body = await utf8.decoder.bind(request).join();
    final Map<String, String> headers = <String, String>{};
    request.headers.forEach((String name, List<String> values) {
      headers[name.toLowerCase()] = values.join(',');
    });
    final StubRequest recorded = StubRequest(
      method: request.method,
      path: request.uri.path,
      headers: headers,
      body: body,
    );
    _requests.add(recorded);

    final StubHandler? handler =
        _routes[_key(request.method, request.uri.path)];
    if (handler == null) {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }

    final StubResponse response = await handler(recorded);
    request.response.statusCode = response.status;
    response.headers.forEach((String name, String value) {
      request.response.headers.set(name, value);
    });
    request.response.write(response.body);
    await request.response.close();
  }

  String _key(String method, String path) => '${method.toUpperCase()} $path';
}

/// Nonce lifecycle states: `active → claimed → consumed|revoked`.
enum AppHandoffNonceState { active, claimed, consumed, revoked }

class _NonceRecord {
  _NonceRecord({
    required this.sub,
    required this.email,
    required this.expiresAt,
  });

  final String sub;
  final String email;
  final DateTime expiresAt;
  AppHandoffNonceState state = AppHandoffNonceState.active;
}

/// A fake identity that the redeem-time user lookup reads.
class AppHandoffUser {
  const AppHandoffUser({
    required this.sub,
    required this.primaryEmail,
    this.isSuspended = false,
    this.deleted = false,
  });

  final String sub;
  final String? primaryEmail;
  final bool isSuspended;

  /// When `true` the lookup behaves like a missing user (`404`).
  final bool deleted;
}

/// The app-handoff mint and redeem fake, mounted on a [StubServer].
///
/// A nonce is single-use with a fixed 15-minute lifetime. Every redeem
/// failure (missing, expired, replayed, deleted, suspended, email changed, or
/// a malformed or unknown-field body) returns the same `AppHandoffExpired`
/// (410) body.
class AppHandoffStub {
  AppHandoffStub({
    required this.problemTypeUri,
    this.mountPath = appHandoffDefaultMount,
    Random? random,
  }) : _random = random ?? Random.secure();

  /// The `type` URI of the `AppHandoffExpired` problem.
  final String problemTypeUri;

  /// The mint route is `POST {mountPath}`, the redeem route
  /// `POST {mountPath}/redeem`.
  final String mountPath;

  /// Nonce lifetime; fixed, not configurable.
  static const Duration nonceTtl = Duration(minutes: 15);

  static const Set<String> _allowedTopKeys = <String>{'nonce', 'device'};
  static const Set<String> _allowedDeviceKeys = <String>{
    'platform',
    'appVersion',
    'osVersion',
    'model',
  };
  static const Set<String> _allowedPlatforms = <String>{'android', 'ios'};

  final Random _random;
  final Map<String, _NonceRecord> _nonces = <String, _NonceRecord>{};
  final Map<String, AppHandoffUser> _users = <String, AppHandoffUser>{};

  /// The identity a mint is attributed to; set it before minting.
  AppHandoffUser? mintingUser;

  /// Registers [user] in the fixture's directory, keyed by its `sub`.
  void addUser(AppHandoffUser user) => _users[user.sub] = user;

  /// The body returned for every redeem failure.
  Map<String, Object?> get expiredBody =>
      AppHandoffExpired.withType(problemTypeUri).toJson();

  /// Registers the mint and redeem routes on [server]; [now] is the clock.
  void mount(StubServer server, {DateTime Function()? now}) {
    final DateTime Function() clock = now ?? DateTime.now;
    server.on('POST', mountPath, (StubRequest request) => _mint(clock));
    server.on(
      'POST',
      '$mountPath/$appHandoffRedeemPath',
      (StubRequest request) => _redeem(request, clock),
    );
  }

  StubResponse _mint(DateTime Function() clock) {
    final AppHandoffUser? user = mintingUser;
    if (user == null) {
      throw StateError('AppHandoffStub.mintingUser must be set before mint');
    }
    final String nonce = _newNonce();
    final DateTime expiresAt = clock().toUtc().add(nonceTtl);
    _nonces[nonce] = _NonceRecord(
      sub: user.sub,
      email: user.primaryEmail ?? '',
      expiresAt: expiresAt,
    );
    return StubResponse.json(
      AppHandoffMint(
        nonce: nonce,
        expiresAt: expiresAt.toIso8601String(),
      ).toJson(),
    );
  }

  StubResponse _redeem(StubRequest request, DateTime Function() clock) {
    final StubResponse expired = StubResponse.json(expiredBody, status: 410);

    final Map<String, Object?> json;
    try {
      json = request.jsonBody();
    } on FormatException {
      return expired;
    }

    // Validate before touching nonce state, so a bad body never claims a nonce.
    final String? nonce = _validatedNonce(json);
    if (nonce == null) return expired;

    final _NonceRecord? record = _nonces[nonce];
    if (record == null ||
        record.state != AppHandoffNonceState.active ||
        !clock().toUtc().isBefore(record.expiresAt)) {
      return expired;
    }
    record.state = AppHandoffNonceState.claimed;

    final AppHandoffUser? user = _users[record.sub];
    final bool ok =
        user != null &&
        !user.deleted &&
        !user.isSuspended &&
        user.primaryEmail != null &&
        user.primaryEmail!.toLowerCase() == record.email.toLowerCase();
    if (!ok) {
      record.state = AppHandoffNonceState.revoked;
      return expired;
    }

    record.state = AppHandoffNonceState.consumed;
    return StubResponse.json(
      AppHandoffRedeemResponse(
        token: 'ott_${_newNonce()}',
        email: user.primaryEmail!,
      ).toJson(),
    );
  }

  String? _validatedNonce(Map<String, Object?> json) {
    for (final String key in json.keys) {
      if (!_allowedTopKeys.contains(key)) return null;
    }
    final Object? nonce = json['nonce'];
    if (nonce is! String) return null;

    final Object? device = json['device'];
    if (device is! Map) return null;
    final Map<String, Object?> dev = device.map(
      (Object? k, Object? v) => MapEntry(k.toString(), v),
    );
    for (final String key in dev.keys) {
      if (!_allowedDeviceKeys.contains(key)) return null;
    }
    final Object? platform = dev['platform'];
    if (platform is! String || !_allowedPlatforms.contains(platform)) {
      return null;
    }
    for (final String optional in const <String>[
      'appVersion',
      'osVersion',
      'model',
    ]) {
      if (dev.containsKey(optional) && dev[optional] is! String) return null;
    }
    return nonce;
  }

  String _newNonce() {
    final List<int> bytes = List<int>.generate(32, (_) => _random.nextInt(256));
    return base64Url.encode(bytes).replaceAll('=', '');
  }
}
