import 'dart:async';

import 'package:diene_problems/diene_problems.dart';
import 'package:diene_result/diene_result.dart';
import '../tokens/resource_key.dart';
import '../tokens/session_tokens.dart';
import 'auth_provider.dart';

/// Resolves access tokens per resource, with a cache and an eager batch.
abstract interface class IAuth {
  /// Resolves one resource's token, serving the cache when still valid.
  Future<Result<ResourceToken>> tokenFor(ResourceKey key);

  /// Starts every key before awaiting any; one entry per distinct key.
  Future<Map<ResourceKey, Result<ResourceToken>>> fetchAllTokens(
    Iterable<ResourceKey> keys,
  );

  /// Drops every cached resource token.
  void invalidateAll();

  /// Drops one resource's cached token.
  void invalidate(ResourceKey key);
}

const Duration _refreshSkew = Duration(seconds: 30);

/// The default [IAuth]: per-key cache; concurrent callers share one fetch.
final class AuthCoordinator implements IAuth {
  AuthCoordinator({required this._provider, DateTime Function()? now})
    : _now = now ?? DateTime.now;

  final AuthProvider _provider;
  final DateTime Function() _now;
  final Map<String, ResourceToken> _cache = <String, ResourceToken>{};
  final Map<String, Future<Result<ResourceToken>>> _inflight =
      <String, Future<Result<ResourceToken>>>{};

  @override
  Future<Result<ResourceToken>> tokenFor(ResourceKey key) {
    final DateTime now = _now().toUtc();
    final ResourceToken? cached = _cache[key.mapKey];
    if (cached != null && cached.expiresAt.isAfter(now.add(_refreshSkew))) {
      return Future<Result<ResourceToken>>.value(Ok<ResourceToken>(cached));
    }
    final Future<Result<ResourceToken>>? pending = _inflight[key.mapKey];
    if (pending != null) {
      return pending;
    }
    final Future<Result<ResourceToken>> acquisition = _acquire(key);
    _inflight[key.mapKey] = acquisition;
    return acquisition.whenComplete(() => _inflight.remove(key.mapKey));
  }

  Future<Result<ResourceToken>> _acquire(ResourceKey key) async {
    try {
      final ResourceToken token = await _provider.resourceToken(key);
      _cache[key.mapKey] = token;
      return Ok<ResourceToken>(token);
    } on Object catch (error) {
      return Err<ResourceToken>(
        Problem(
          type: 'urn:diene:problem:resource-token',
          title: 'Could not acquire a resource token',
          status: 401,
          detail: error.toString(),
          recoverable: true,
          data: <String, Object?>{'resource': key.mapKey},
        ),
      );
    }
  }

  @override
  Future<Map<ResourceKey, Result<ResourceToken>>> fetchAllTokens(
    Iterable<ResourceKey> keys,
  ) async {
    final Map<String, ResourceKey> unique = <String, ResourceKey>{};
    for (final ResourceKey key in keys) {
      unique[key.mapKey] = key;
    }
    final Map<ResourceKey, Future<Result<ResourceToken>>> started =
        <ResourceKey, Future<Result<ResourceToken>>>{
          for (final ResourceKey key in unique.values) key: tokenFor(key),
        };
    final Map<ResourceKey, Result<ResourceToken>> results =
        <ResourceKey, Result<ResourceToken>>{};
    for (final MapEntry<ResourceKey, Future<Result<ResourceToken>>> entry
        in started.entries) {
      results[entry.key] = await entry.value;
    }
    return results;
  }

  @override
  void invalidate(ResourceKey key) => _cache.remove(key.mapKey);

  @override
  void invalidateAll() => _cache.clear();
}
