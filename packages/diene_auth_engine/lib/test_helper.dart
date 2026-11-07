/// Fakes, builders and plain-throw assertions; no test framework needed.
library;

import 'dart:convert';

import 'package:diene_problems/diene_problems.dart';
import 'package:diene_result/diene_result.dart';
import 'package:http/http.dart' as http;

import 'src/auth/auth_provider.dart';
import 'src/auth/auth_seam.dart';
import 'src/auth/claims.dart';
import 'src/config/auth_engine_config.dart';
import 'src/deferred/deferred_login.dart';
import 'src/deferred/redeem_client.dart';
import 'src/home/home_claim.dart';
import 'src/home/landscape_selector.dart';
import 'src/onboarding/onboarding_phase.dart';
import 'src/onboarding/user_directory.dart';
import 'src/tokens/resource_key.dart';
import 'src/tokens/session_tokens.dart';
import 'src/tokens/token_lifetimes.dart';

/// Thrown by the [AuthExpect] assertions.
final class AuthAssertionError extends Error {
  AuthAssertionError(this.message);

  final String message;

  @override
  String toString() => 'AuthAssertionError: $message';
}

/// Plain-throw assertions for results, options and phases.
abstract final class AuthExpect {
  static T ok<T>(Result<T> result, {String? reason}) => result.match(
    ok: (T value) => value,
    err: (Problem problem) =>
        throw AuthAssertionError(reason ?? 'expected Ok but got Err($problem)'),
  );

  static Problem err<T>(Result<T> result, {String? reason}) => result.match(
    ok: (T value) =>
        throw AuthAssertionError(reason ?? 'expected Err but got Ok($value)'),
    err: (Problem problem) => problem,
  );

  static Problem errType<T>(Result<T> result, String type) {
    final Problem problem = err(result);
    if (problem.type != type) {
      throw AuthAssertionError(
        'expected Err type "$type" but got "${problem.type}"',
      );
    }
    return problem;
  }

  static T some<T>(Option<T> option, {String? reason}) => option.match(
    some: (T value) => value,
    none: () =>
        throw AuthAssertionError(reason ?? 'expected Some but got None'),
  );

  static void none<T>(Option<T> option, {String? reason}) => option.match(
    some: (T value) => throw AuthAssertionError(
      reason ?? 'expected None but got Some($value)',
    ),
    none: () {},
  );

  static void phase(OnboardingPhase actual, OnboardingPhase expected) {
    if (actual != expected) {
      throw AuthAssertionError('expected phase $expected but got $actual');
    }
  }

  static void status(Problem problem, int expected) {
    if (problem.status != expected) {
      throw AuthAssertionError(
        'expected status $expected but got ${problem.status}',
      );
    }
  }
}

/// Builders for tokens, claims and resource keys.
abstract final class AuthFixtures {
  /// An unsigned JWT whose payload is [claims].
  static String jwt(Map<String, Object?> claims) {
    String seg(Map<String, Object?> value) =>
        base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
    final String header = seg(<String, Object?>{'alg': 'none', 'typ': 'JWT'});
    final String payload = seg(claims);
    return '$header.$payload.sig';
  }

  /// A JWT with the registration claim for [key], plus [extra].
  static String registeredJwt(
    ResourceKey key, {
    Map<String, Object?> extra = const <String, Object?>{},
  }) => jwt(<String, Object?>{
    Claims.registrationKey(platform: key.platform, service: key.service):
        'true',
    ...extra,
  });

  static String unregisteredJwt(
    ResourceKey key, {
    Map<String, Object?> extra = const <String, Object?>{},
  }) => jwt(<String, Object?>{...extra});

  /// A session with the standard lifetimes, starting at [now].
  static SessionTokens sessionTokens({
    required DateTime now,
    String accessToken = 'access',
    String refreshToken = 'refresh',
    String refreshFamily = 'family',
    Duration access = TokenLifetimes.access,
    Duration refresh = TokenLifetimes.refresh,
  }) {
    final DateTime base = now.toUtc();
    return SessionTokens(
      accessToken: accessToken,
      refreshToken: refreshToken,
      refreshFamily: refreshFamily,
      accessExpiresAt: base.add(access),
      refreshExpiresAt: base.add(refresh),
    );
  }

  static ResourceToken resourceToken({
    required DateTime now,
    required String jwtToken,
    Duration ttl = TokenLifetimes.access,
  }) => ResourceToken(token: jwtToken, expiresAt: now.toUtc().add(ttl));

  static ResourceKey resourceKey({
    String platform = 'lithium',
    String landscape = 'lapras',
    String service = 'api',
    String resourceName = 'root',
  }) => ResourceKey(
    platform: platform,
    landscape: landscape,
    service: service,
    resourceName: resourceName,
  );
}

/// A scriptable [AuthProvider] that counts its calls.
final class FakeAuthProvider implements AuthProvider {
  FakeAuthProvider({
    this._onSignIn,
    this._onRefresh,
    this._onReMint,
    Map<String, ResourceToken>? resourceTokens,
    this._idTokenValue,
    this._throwOnSignIn,
    this._freshClaimTokenValue,
    this._onFreshClaimToken,
  }) : _resourceTokens = resourceTokens ?? <String, ResourceToken>{};

  final SessionTokens Function()? _onSignIn;
  final SessionTokens Function(SessionTokens current)? _onRefresh;
  final SessionTokens Function(SessionTokens current)? _onReMint;
  final Map<String, ResourceToken> _resourceTokens;
  final String? _idTokenValue;
  final Object? _throwOnSignIn;
  final String? _freshClaimTokenValue;
  final Future<String?> Function()? _onFreshClaimToken;

  int signInCount = 0;
  int refreshCount = 0;
  int reMintCount = 0;
  int signOutCount = 0;
  int freshClaimTokenCount = 0;
  Map<String, String> lastExtraParams = const <String, String>{};

  @override
  Future<SessionTokens> signIn({
    Map<String, String> extraParams = const <String, String>{},
  }) async {
    signInCount += 1;
    lastExtraParams = extraParams;
    if (_throwOnSignIn != null) {
      throw _throwOnSignIn;
    }
    return (_onSignIn ?? (() => throw StateError('no signIn scripted')))();
  }

  @override
  Future<SessionTokens> refresh(SessionTokens current) async {
    refreshCount += 1;
    return (_onRefresh ?? (SessionTokens c) => throw StateError('no refresh'))(
      current,
    );
  }

  @override
  Future<SessionTokens> reMintOnOpen(SessionTokens current) async {
    reMintCount += 1;
    return (_onReMint ?? (SessionTokens c) => throw StateError('no reMint'))(
      current,
    );
  }

  @override
  Future<void> signOut() async => signOutCount += 1;

  @override
  Future<ResourceToken> resourceToken(ResourceKey key) async {
    final ResourceToken? token = _resourceTokens[key.mapKey];
    if (token == null) {
      throw StateError('no resource token scripted for ${key.mapKey}');
    }
    return token;
  }

  @override
  Future<String?> idToken() async => _idTokenValue;

  @override
  Future<String?> freshClaimToken() async {
    freshClaimTokenCount += 1;
    if (_onFreshClaimToken != null) {
      return _onFreshClaimToken();
    }
    return _freshClaimTokenValue;
  }
}

/// A scriptable [IAuth]; each [fetchAllTokens] call takes the next batch.
final class FakeAuth implements IAuth {
  FakeAuth(this.batches)
    : assert(batches.isNotEmpty, 'at least one batch is required');

  final List<Map<ResourceKey, Result<ResourceToken>>> batches;
  int _cursor = 0;
  int fetchAllCount = 0;
  int invalidateAllCount = 0;
  final List<String> invalidated = <String>[];

  Map<ResourceKey, Result<ResourceToken>> get _current =>
      batches[_cursor.clamp(0, batches.length - 1)];

  @override
  Future<Result<ResourceToken>> tokenFor(ResourceKey key) async {
    final Result<ResourceToken>? result = _current[key];
    return result ??
        Err<ResourceToken>(
          Problem(
            type: 'urn:diene:problem:resource-token',
            title: 'No token scripted',
            status: 401,
            data: <String, Object?>{'resource': key.mapKey},
          ),
        );
  }

  @override
  Future<Map<ResourceKey, Result<ResourceToken>>> fetchAllTokens(
    Iterable<ResourceKey> keys,
  ) async {
    fetchAllCount += 1;
    final Map<ResourceKey, Result<ResourceToken>> snapshot = _current;
    if (_cursor < batches.length - 1) {
      _cursor += 1;
    }
    return <ResourceKey, Result<ResourceToken>>{
      for (final ResourceKey key in keys)
        key: snapshot[key] ?? await tokenFor(key),
    };
  }

  @override
  void invalidate(ResourceKey key) => invalidated.add(key.mapKey);

  @override
  void invalidateAll() => invalidateAllCount += 1;
}

/// A scriptable [UserDirectory] that counts its calls.
final class FakeUserDirectory implements UserDirectory {
  FakeUserDirectory({
    this.getStatus = 200,
    this.postStatus = 201,
    this.throwOnGet = false,
  });

  int getStatus;
  int postStatus;
  bool throwOnGet;
  int getCount = 0;
  int postCount = 0;

  @override
  Future<int> getUserMe({
    required String backendId,
    required String accessToken,
  }) async {
    getCount += 1;
    if (throwOnGet) {
      throw StateError('directory transport failure');
    }
    return getStatus;
  }

  @override
  Future<int> postUser({
    required String backendId,
    required String accessToken,
    required String idToken,
  }) async {
    postCount += 1;
    return postStatus;
  }
}

/// A scriptable [AppHandoffApi].
final class FakeAppHandoffApi implements AppHandoffApi {
  FakeAppHandoffApi({Result<RedeemResult>? result})
    : _result = result ?? Err<RedeemResult>(appHandoffExpired());

  final Result<RedeemResult> _result;
  int redeemCount = 0;
  String? lastNonce;

  @override
  Future<Result<RedeemResult>> redeem({
    required String nonce,
    required DeviceInfo device,
  }) async {
    redeemCount += 1;
    lastNonce = nonce;
    return _result;
  }
}

/// A Doc B source that returns [doc] or throws [error].
final class FakeLandscapeSelectorSource implements LandscapeSelectorSource {
  FakeLandscapeSelectorSource({this.doc, this.error});

  LandscapeSelectorDoc? doc;
  Object? error;
  int fetchCount = 0;

  @override
  Future<LandscapeSelectorDoc> fetch() async {
    fetchCount += 1;
    if (error != null) {
      throw error!;
    }
    return doc ?? (throw StateError('no landscape doc scripted'));
  }
}

/// A pinger by landscape name; `null` or a missing name is unhealthy.
final class FakeRegionPinger implements RegionPinger {
  FakeRegionPinger(this.latencies);

  final Map<String, Duration?> latencies;
  final List<String> pinged = <String>[];

  @override
  Future<Duration?> ping(LandscapeEntry entry) async {
    pinged.add(entry.name);
    return latencies[entry.name];
  }
}

/// An in-memory [HomeClaimStore].
final class MemoryHomeClaimStore implements HomeClaimStore {
  MemoryHomeClaimStore([this.value]);

  String? value;
  int reads = 0;
  int writes = 0;

  @override
  Future<String?> read() async {
    reads += 1;
    return value;
  }

  @override
  Future<void> write(String landscape) async {
    writes += 1;
    value = landscape;
  }

  @override
  Future<void> clear() async {
    value = null;
  }
}

/// A scriptable Install Referrer source.
final class FakeInstallReferrerSource implements InstallReferrerSource {
  FakeInstallReferrerSource(this.referrer);

  String? referrer;
  bool processed = false;

  @override
  Future<String?> read() async => referrer;

  @override
  Future<void> markProcessed() async => processed = true;
}

/// A scriptable iOS clipboard source.
final class FakeClipboardCarrierSource implements ClipboardCarrierSource {
  FakeClipboardCarrierSource(this.contents);

  String? contents;
  bool cleared = false;

  @override
  Future<String?> read() async => contents;

  @override
  Future<void> clearIfEquals(String value) async {
    if (contents?.trim() == value) {
      contents = null;
      cleared = true;
    }
  }
}

/// An HTTP stub that answers only `POST {mount}/redeem` with a valid body.
///
/// Any other path, including a doubled `app-handoff` segment, gets 404; a body
/// with an unknown key or a bad nonce gets 400.
final class FakeRedeemHttpClient extends http.BaseClient {
  FakeRedeemHttpClient({
    this.mount = AppHandoffConstants.defaultMount,
    this.token = 'one-time-token',
    this.email = 'user@example.com',
    this.status = 200,
  });

  final String mount;
  final String token;
  final String email;
  int status;
  final List<Uri> requests = <Uri>[];
  final List<Map<String, Object?>> bodies = <Map<String, Object?>>[];

  static const Set<String> _bodyKeys = <String>{'nonce', 'device'};
  static const Set<String> _deviceKeys = <String>{
    'platform',
    'appVersion',
    'osVersion',
    'model',
  };
  static final RegExp _nonce = RegExp(r'^[A-Za-z0-9_-]{43}$');

  /// Whether [body] is a well-formed redeem request.
  static bool acceptsBody(Map<String, Object?> body) {
    final Object? device = body['device'];
    final Object? nonce = body['nonce'];
    return _bodyKeys.containsAll(body.keys) &&
        nonce is String &&
        _nonce.hasMatch(nonce) &&
        device is Map &&
        device['platform'] is String &&
        _deviceKeys.containsAll(device.keys);
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests.add(request.url);
    final String raw = request is http.Request ? request.body : '';
    final Object? decoded = raw.isEmpty ? null : jsonDecode(raw);
    final Map<String, Object?> body = decoded is Map<String, Object?>
        ? decoded
        : <String, Object?>{};
    bodies.add(body);
    if (request.method != 'POST' || request.url.path != '$mount/redeem') {
      return _reply(404, <String, Object?>{});
    }
    if (!acceptsBody(body)) {
      return _reply(400, <String, Object?>{});
    }
    if (status != 200) {
      return _reply(status, <String, Object?>{});
    }
    return _reply(200, <String, Object?>{
      'token': token,
      'email': email,
      'expiresIn': AppHandoffConstants.oneTimeTokenExpiresInSeconds,
    });
  }

  http.StreamedResponse _reply(int code, Map<String, Object?> json) =>
      http.StreamedResponse(
        Stream<List<int>>.value(utf8.encode(jsonEncode(json))),
        code,
        headers: const <String, String>{'content-type': 'application/json'},
      );
}
