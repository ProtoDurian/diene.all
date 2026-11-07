import 'package:diene_problems/diene_problems.dart';
import 'package:diene_result/diene_result.dart';

import '../auth/auth_seam.dart';
import '../auth/claims.dart';
import '../tokens/resource_key.dart';
import '../tokens/session_tokens.dart';
import 'backend_registry.dart';
import 'user_directory.dart';

/// One backend's onboarding phase; there is no global onboarded flag.
enum OnboardingPhase { bootstrapping, needsOnboarding, ready, error }

/// Reads the raw ID token for the `POST /User` body.
typedef IdTokenReader = Future<String?> Function();

/// Runs claims-first onboarding for one backend; failures stay with it.
final class OnboardingMachine {
  OnboardingMachine({
    required this._backend,
    required this._auth,
    required this._directory,
    required this._idToken,
  });

  final RegisteredBackend _backend;
  final IAuth _auth;
  final UserDirectory _directory;
  final IdTokenReader _idToken;

  OnboardingPhase _phase = OnboardingPhase.bootstrapping;
  OnboardingPhase get phase => _phase;

  String get backendId => _backend.backendId;

  List<ResourceKey> get resources => _backend.resources;

  /// Runs to a terminal phase; [initialBatch] is this backend's shared slice.
  Future<Result<OnboardingPhase>> run({
    Map<ResourceKey, Result<ResourceToken>>? initialBatch,
  }) async {
    _phase = OnboardingPhase.bootstrapping;
    final Map<ResourceKey, Result<ResourceToken>> batch =
        initialBatch ?? await _auth.fetchAllTokens(_backend.resources);
    final Problem? batchProblem = _firstFailure(batch);
    if (batchProblem != null) {
      return _error(batchProblem);
    }

    if (_allRegistered(batch)) {
      return _settleRegistered(batch);
    }

    // A claim is absent: only now call `GET /User/Me`.
    final ResourceToken onboarding =
        (batch[_backend.onboardingResource]! as Ok<ResourceToken>).value;
    try {
      final int getStatus = await _directory.getUserMe(
        backendId: _backend.backendId,
        accessToken: onboarding.token,
      );
      if (getStatus == 404) {
        final String? idToken = await _idToken();
        if (idToken == null) {
          return _error(
            const Problem(
              type: 'urn:diene:problem:onboarding-idtoken',
              title: 'Missing ID token for onboarding create',
              status: 401,
            ),
          );
        }
        final int postStatus = await _directory.postUser(
          backendId: _backend.backendId,
          accessToken: onboarding.token,
          idToken: idToken,
        );
        final bool createdOrOk =
            (postStatus >= 200 && postStatus < 300) || postStatus == 409;
        if (!createdOrOk) {
          return _error(_httpProblem('POST /User', postStatus));
        }
      } else if (getStatus != 200) {
        return _error(_httpProblem('GET /User/Me', getStatus));
      }
    } on Object catch (error) {
      return _error(
        Problem(
          type: 'urn:diene:problem:onboarding-transport',
          title: 'Onboarding request failed',
          status: 503,
          detail: error.toString(),
          recoverable: true,
        ),
      );
    }

    // Refetch every token and re-check the claim.
    for (final ResourceKey key in _backend.resources) {
      _auth.invalidate(key);
    }
    final Map<ResourceKey, Result<ResourceToken>> refreshed = await _auth
        .fetchAllTokens(_backend.resources);
    final Problem? refreshProblem = _firstFailure(refreshed);
    if (refreshProblem != null) {
      return _error(refreshProblem);
    }
    if (_allRegistered(refreshed)) {
      return _settleRegistered(refreshed);
    }
    return _error(
      const Problem(
        type: 'urn:diene:problem:onboarding-claim-missing',
        title: 'OnboardingClaimMissing',
        status: 409,
      ),
    );
  }

  /// A present claim later met 401/404: an ordinary error, no re-create.
  Result<OnboardingPhase> markStaleClaim() => _error(
    const Problem(
      type: 'urn:diene:problem:onboarding-stale-claim',
      title: 'Stale onboarding claim',
      status: 401,
    ),
  );

  Result<OnboardingPhase> _settleRegistered(
    Map<ResourceKey, Result<ResourceToken>> batch,
  ) {
    final String? appClaim = _backend.appOnboardingClaim;
    if (appClaim != null) {
      final ResourceToken onboarding =
          (batch[_backend.onboardingResource]! as Ok<ResourceToken>).value;
      final Map<String, Object?> claims = Claims.decode(onboarding.token);
      final Object? value = claims[appClaim];
      final bool present = value is String && value == 'true';
      if (!present) {
        _phase = OnboardingPhase.needsOnboarding;
        return Ok<OnboardingPhase>(_phase);
      }
    }
    _phase = OnboardingPhase.ready;
    return Ok<OnboardingPhase>(_phase);
  }

  bool _allRegistered(Map<ResourceKey, Result<ResourceToken>> batch) {
    for (final ResourceKey key in _backend.resources) {
      final ResourceToken token = (batch[key]! as Ok<ResourceToken>).value;
      final Map<String, Object?> claims = Claims.decode(token.token);
      if (!Claims.hasRegistration(
        claims,
        platform: key.platform,
        service: key.service,
      )) {
        return false;
      }
    }
    return true;
  }

  Problem? _firstFailure(Map<ResourceKey, Result<ResourceToken>> batch) {
    for (final Result<ResourceToken> result in batch.values) {
      if (result is Err<ResourceToken>) {
        return result.problem;
      }
    }
    return null;
  }

  Problem _httpProblem(String call, int status) => Problem(
    type: 'urn:diene:problem:onboarding-http',
    title: 'Onboarding call failed',
    status: status,
    detail: '$call returned $status',
    data: <String, Object?>{'call': call, 'status': status},
  );

  Result<OnboardingPhase> _error(Problem problem) {
    _phase = OnboardingPhase.error;
    return Err<OnboardingPhase>(problem);
  }
}

/// One [OnboardingMachine] per backend; phases and tokens never bleed.
final class MultiBackendOnboarding {
  MultiBackendOnboarding({
    required BackendRegistry registry,
    required IAuth auth,
    required UserDirectory directory,
    required IdTokenReader idToken,
  }) : _registry = registry,
       _auth = auth,
       _machines = <String, OnboardingMachine>{
         for (final RegisteredBackend backend in registry.backends)
           backend.backendId: OnboardingMachine(
             backend: backend,
             auth: auth,
             directory: directory,
             idToken: idToken,
           ),
       };

  final BackendRegistry _registry;
  final IAuth _auth;
  final Map<String, OnboardingMachine> _machines;

  OnboardingMachine machineFor(String backendId) {
    final OnboardingMachine? machine = _machines[backendId];
    if (machine == null) {
      throw ArgumentError.value(backendId, 'backendId', 'unregistered backend');
    }
    return machine;
  }

  Map<String, OnboardingPhase> get phases => <String, OnboardingPhase>{
    for (final MapEntry<String, OnboardingMachine> entry in _machines.entries)
      entry.key: entry.value.phase,
  };

  /// Bootstraps every backend from one deduplicated token batch.
  Future<Map<String, Result<OnboardingPhase>>> runAll() async {
    final List<ResourceKey> union = _registry.resourceUnion;
    final Map<ResourceKey, Result<ResourceToken>> unionBatch = await _auth
        .fetchAllTokens(union);

    final Map<String, Future<Result<OnboardingPhase>>> started =
        <String, Future<Result<OnboardingPhase>>>{
          for (final MapEntry<String, OnboardingMachine> entry
              in _machines.entries)
            entry.key: entry.value.run(
              initialBatch: _project(entry.value, unionBatch),
            ),
        };
    final Map<String, Result<OnboardingPhase>> results =
        <String, Result<OnboardingPhase>>{};
    for (final MapEntry<String, Future<Result<OnboardingPhase>>> entry
        in started.entries) {
      results[entry.key] = await entry.value;
    }
    return results;
  }

  Map<ResourceKey, Result<ResourceToken>> _project(
    OnboardingMachine machine,
    Map<ResourceKey, Result<ResourceToken>> unionBatch,
  ) => <ResourceKey, Result<ResourceToken>>{
    for (final ResourceKey key in machine.resources)
      if (unionBatch.containsKey(key)) key: unionBatch[key]!,
  };
}
