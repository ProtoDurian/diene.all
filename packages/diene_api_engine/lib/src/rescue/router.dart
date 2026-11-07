import 'dart:async';
import 'dart:convert';
import 'dart:math';

import '../config.dart';
import '../transport.dart';
import 'docs.dart';
import 'store.dart';

/// Result of a rescue attempt.
sealed class RescueOutcome {
  const RescueOutcome();
}

/// A healthy address for the same backend in the same landscape.
final class Rescued extends RescueOutcome {
  const Rescued(this.baseUrl, {required this.fromLastKnownGood});

  final Uri baseUrl;
  final bool fromLastKnownGood;
}

/// No healthy address was found; [reason] says why.
final class RescueUnavailable extends RescueOutcome {
  const RescueUnavailable(this.reason);

  final String reason;
}

/// The dormant rescue router: runs only after a hard failure survives the
/// retry, and only when [RescueConfig.enabled] is true.
class RescueRouter {
  RescueRouter({
    required this.config,
    required this.store,
    required this.transport,
    Future<void> Function(Duration duration)? sleep,
    int Function()? nowMs,
    Duration Function()? jitter,
    Random? random,
  }) : _sleep = sleep ?? Future<void>.delayed,
       _nowMs = nowMs ?? _wallClockMs,
       _random = random ?? Random(),
       _jitterOverride = jitter;

  final RescueConfig config;
  final RescueStore store;
  final HttpTransport transport;
  final Future<void> Function(Duration duration) _sleep;
  final int Function() _nowMs;
  final Random _random;
  final Duration Function()? _jitterOverride;

  static int _wallClockMs() => DateTime.now().millisecondsSinceEpoch;

  static const String _docAVersionKey = 'doca.version';

  // Doc C is cached per platform and landscape so backends never share one.
  String _docCScope(LpsmCoordinate c) => '${c.platform}.${c.landscape}';
  String _docCKey(LpsmCoordinate c) => 'docc.${_docCScope(c)}';
  String _docCVersionKey(LpsmCoordinate c) => 'docc.version.${_docCScope(c)}';
  String _pinKey(LpsmCoordinate c) => 'pin.${c.key}';
  String _lastGoodKey(LpsmCoordinate c) => 'lastgood.${c.key}';

  /// The baked issuer; never read from a document.
  Uri get bakedIssuer => config.issuer;

  /// A jitter in `[0, maxJitter]`, or the injected one.
  Duration nextJitter() {
    if (_jitterOverride != null) {
      return _jitterOverride();
    }
    final int maxMs = config.maxJitter.inMilliseconds;
    return maxMs <= 0
        ? Duration.zero
        : Duration(milliseconds: _random.nextInt(maxMs + 1));
  }

  /// True when [url]'s host matches a baked allowed suffix.
  bool isAllowed(Uri url) {
    final String host = url.host;
    if (host.isEmpty) {
      return false;
    }
    return config.endpointSuffixAllowlist.any(
      (String suffix) => host == suffix || host.endsWith(suffix),
    );
  }

  /// The pinned rescue address for [coordinate], if still allowed.
  Future<Uri?> pinnedFor(LpsmCoordinate coordinate) async {
    final String? raw = await store.read(_pinKey(coordinate));
    final Uri? url = raw == null ? null : Uri.tryParse(raw);
    return url != null && isAllowed(url) ? url : null;
  }

  /// Clears the pin once the primary heals.
  Future<void> onPrimaryHealed(LpsmCoordinate coordinate) =>
      store.delete(_pinKey(coordinate));

  /// True when [baseUrl] answers with a status below 500.
  Future<bool> probeHealthy(Uri baseUrl) async {
    final TransportOutcome outcome = await transport.send(
      HttpRequest(method: HttpMethod.head, url: baseUrl),
    );
    return outcome is Received && outcome.response.status < 500;
  }

  /// Finds a healthy address for [coordinate] in its own landscape.
  Future<RescueOutcome> rescue(LpsmCoordinate coordinate) async {
    if (!config.enabled) {
      return const RescueUnavailable('rescue disabled for this context');
    }

    final DocC? docC = await _loadOrRefreshDocC(coordinate);
    final Uri? lastGood = await _lastKnownGood(coordinate);

    final List<Uri> candidates = <Uri>[
      if (docC != null)
        ...?docC.candidates[coordinate.key]
            ?.map(Uri.tryParse)
            .nonNulls
            .where(isAllowed),
    ];

    final int start = _nowMs();
    final int deadline = start + config.scanBudget.inMilliseconds;
    for (final Uri candidate in candidates) {
      await _sleep(nextJitter());
      final int remaining = deadline - _nowMs();
      if (remaining <= 0) {
        break;
      }
      final Duration cap = Duration(
        milliseconds: remaining < config.perCandidateTimeout.inMilliseconds
            ? remaining
            : config.perCandidateTimeout.inMilliseconds,
      );
      if (await _probeWithinBudget(candidate, cap)) {
        await _pin(coordinate, candidate);
        return Rescued(candidate, fromLastKnownGood: false);
      }
    }

    if (lastGood != null && isAllowed(lastGood)) {
      return Rescued(lastGood, fromLastKnownGood: true);
    }
    return const RescueUnavailable(
      'no healthy candidate within budget and no last-known-good',
    );
  }

  // A probe that hangs or throws counts as unhealthy once [cap] passes.
  Future<bool> _probeWithinBudget(Uri candidate, Duration cap) async {
    final Completer<bool> done = Completer<bool>();
    unawaited(
      probeHealthy(candidate).then(
        (bool healthy) {
          if (!done.isCompleted) {
            done.complete(healthy);
          }
        },
        onError: (_, _) {
          if (!done.isCompleted) {
            done.complete(false);
          }
        },
      ),
    );
    unawaited(
      _sleep(cap).then((_) {
        if (!done.isCompleted) {
          done.complete(false);
        }
      }),
    );
    return done.future;
  }

  Future<Uri?> _lastKnownGood(LpsmCoordinate coordinate) async {
    final String? raw = await store.read(_lastGoodKey(coordinate));
    return raw == null ? null : Uri.tryParse(raw);
  }

  Future<void> _pin(LpsmCoordinate coordinate, Uri url) async {
    await store.write(_pinKey(coordinate), url.toString());
    await store.write(_lastGoodKey(coordinate), url.toString());
  }

  // Doc C is refreshed per scope whatever Doc A's version does.
  Future<DocC?> _loadOrRefreshDocC(LpsmCoordinate coordinate) async {
    DocC? cached;
    final String? cachedRaw = await store.read(_docCKey(coordinate));
    if (cachedRaw != null) {
      cached = DocC.tryDecode(cachedRaw);
    }
    final int? seenDocC = _parseInt(
      await store.read(_docCVersionKey(coordinate)),
    );

    final DocA? docA = await _fetchDocA();
    if (docA != null) {
      final DocC? fetched = await _fetchDocC(docA, coordinate);
      if (fetched != null && _isNewer(fetched.version, seenDocC)) {
        await store.write(_docCKey(coordinate), fetched.encode());
        await store.write(
          _docCVersionKey(coordinate),
          fetched.version.toString(),
        );
        return fetched;
      }
    }
    return cached;
  }

  // An older Doc A is a rollback and is refused.
  Future<DocA?> _fetchDocA() async {
    final int? seenDocA = _parseInt(await store.read(_docAVersionKey));
    for (final String host in config.catalogHosts) {
      final Uri? url = _hostUri(host, '/fleet.json');
      if (url == null || !isAllowed(url)) {
        continue;
      }
      final TransportOutcome? outcome = await _sendOrNull(url);
      if (outcome == null) {
        continue;
      }
      if (outcome is Received && outcome.response.status == 200) {
        final Map<String, Object?>? json = _jsonObject(outcome.response.body);
        if (json != null &&
            json['catalogHosts'] is List &&
            json['version'] is num &&
            (json['version']! as num).isFinite) {
          final DocA docA = DocA.fromJson(json);
          if (seenDocA != null && docA.version < seenDocA) {
            return null;
          }
          if (_isNewer(docA.version, seenDocA)) {
            await store.write(_docAVersionKey, docA.version.toString());
          }
          return docA;
        }
      }
    }
    return null;
  }

  Future<DocC?> _fetchDocC(DocA docA, LpsmCoordinate coordinate) async {
    final String path = '/catalog/${coordinate.platform}.json';
    for (final String host in docA.catalogHosts) {
      final Uri? url = _hostUri(host, path);
      if (url == null || !isAllowed(url)) {
        continue;
      }
      final TransportOutcome? outcome = await _sendOrNull(url);
      if (outcome == null) {
        continue;
      }
      if (outcome is Received && outcome.response.status == 200) {
        final DocC? doc = DocC.tryDecode(outcome.response.body);
        if (doc != null) {
          return doc;
        }
      }
    }
    return null;
  }

  // A transport that throws breaks its contract; skip that host.
  Future<TransportOutcome?> _sendOrNull(Uri url) async {
    try {
      return await transport.send(
        HttpRequest(method: HttpMethod.get, url: url),
      );
    } on Object {
      return null;
    }
  }

  Uri? _hostUri(String host, String path) => host.contains('://')
      ? Uri.tryParse('$host$path')
      : Uri.tryParse('https://$host$path');

  static Map<String, Object?>? _jsonObject(String body) {
    if (body.trim().isEmpty) {
      return null;
    }
    try {
      final Object? decoded = jsonDecode(body);
      return decoded is Map<String, Object?> ? decoded : null;
    } on FormatException {
      return null;
    }
  }

  static bool _isNewer(int candidate, int? seen) =>
      seen == null || candidate > seen;

  static int? _parseInt(String? raw) => raw == null ? null : int.tryParse(raw);
}
