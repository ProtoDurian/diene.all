import 'package:diene_problems/diene_problems.dart';
import 'package:diene_result/diene_result.dart';

/// One Doc B landscape: a name, a region and metadata, never an address.
final class LandscapeEntry {
  const LandscapeEntry({
    required this.name,
    required this.region,
    this.metadata = const <String, Object?>{},
  });

  final String name;
  final String region;
  final Map<String, Object?> metadata;
}

/// Doc B, the landscape selector document: `{ platform, tier, landscapes }`.
final class LandscapeSelectorDoc {
  const LandscapeSelectorDoc({
    required this.platform,
    required this.tier,
    required this.landscapes,
  });

  /// Parses Doc B; any address, issuer, URL or bad shape rejects the whole doc.
  factory LandscapeSelectorDoc.fromJson(Map<String, Object?> json) {
    final Set<String> unknown = json.keys.toSet().difference(
      _allowedTopLevelKeys,
    );
    if (unknown.isNotEmpty) {
      throw FormatException(
        'Doc B must carry exactly landscapes/platform/tier',
        unknown.join(','),
      );
    }

    final Object? rawPlatform = json['platform'];
    if (rawPlatform is! String || rawPlatform.isEmpty) {
      throw const FormatException('Doc B platform must be a non-empty string');
    }
    final Object? rawTier = json['tier'];
    if (rawTier is! String || rawTier.isEmpty) {
      throw const FormatException('Doc B tier must be a non-empty string');
    }

    final Object? rawList = json['landscapes'];
    if (rawList is! List) {
      throw const FormatException('Doc B must carry a landscapes list');
    }
    final List<LandscapeEntry> entries = <LandscapeEntry>[];
    for (final Object? item in rawList) {
      if (item is! Map) {
        throw const FormatException('Doc B landscape entry must be a map');
      }
      final Map<String, Object?> entry = item.map(
        (Object? key, Object? value) => MapEntry(key.toString(), value),
      );
      _assertNoProhibited(entry);

      final Object? name = entry['name'];
      final Object? region = entry['region'];
      if (name is! String || name.isEmpty || region is! String) {
        throw const FormatException('Doc B entry needs a name and region');
      }
      entries.add(
        LandscapeEntry(
          name: name,
          region: region,
          metadata:
              (entry['metadata'] as Map<Object?, Object?>? ??
                      const <Object?, Object?>{})
                  .map(
                    (Object? key, Object? value) =>
                        MapEntry(key.toString(), value),
                  ),
        ),
      );
    }
    return LandscapeSelectorDoc(
      platform: rawPlatform,
      tier: rawTier,
      landscapes: entries,
    );
  }

  static const Set<String> _allowedTopLevelKeys = <String>{
    'landscapes',
    'platform',
    'tier',
  };

  static const Set<String> _forbiddenKeys = <String>{
    'address',
    'addresses',
    'host',
    'hosts',
    'hostname',
    'url',
    'uri',
    'href',
    'endpoint',
    'endpoints',
    'issuer',
    'authority',
    'origin',
    'ip',
    'ipaddress',
  };

  static void _assertNoProhibited(Object? node) {
    if (node is Map) {
      node.forEach((Object? key, Object? value) {
        if (_forbiddenKeys.contains(key.toString().toLowerCase())) {
          throw FormatException(
            'Doc B must not carry addresses/issuer/URLs',
            key.toString(),
          );
        }
        _assertNoProhibited(value);
      });
    } else if (node is List) {
      for (final Object? element in node) {
        _assertNoProhibited(element);
      }
    } else if (node is String && _looksLikeUrl(node)) {
      throw FormatException('Doc B must not carry a URL/address value', node);
    }
  }

  static bool _looksLikeUrl(String value) {
    final String v = value.trim().toLowerCase();
    if (v.startsWith('//') || v.contains('://')) {
      return true;
    }
    return v.startsWith('http:') || v.startsWith('https:');
  }

  final String platform;
  final String tier;
  final List<LandscapeEntry> landscapes;
}

/// Fetches Doc B.
abstract interface class LandscapeSelectorSource {
  Future<LandscapeSelectorDoc> fetch();
}

/// Pings one region; `null` when unhealthy. Ping URLs come from the name.
abstract interface class RegionPinger {
  Future<Duration?> ping(LandscapeEntry entry);
}

/// Picks the home landscape from Doc B: ping each region, take the fastest.
///
/// A healthy [preferred] name wins. It is never a per-request router.
final class LandscapeSelectorClient {
  const LandscapeSelectorClient({required this._source, required this._pinger});

  final LandscapeSelectorSource _source;
  final RegionPinger _pinger;

  Future<Result<String>> selectHome({String? preferred}) async {
    final LandscapeSelectorDoc doc;
    try {
      doc = await _source.fetch();
    } on Object catch (error) {
      return Err<String>(
        Problem(
          type: 'urn:diene:problem:landscape-doc',
          title: 'Could not fetch the landscape selector',
          status: 503,
          detail: error.toString(),
          recoverable: true,
        ),
      );
    }
    if (doc.landscapes.isEmpty) {
      return const Err<String>(
        Problem(
          type: 'urn:diene:problem:landscape-empty',
          title: 'No landscapes offered',
          status: 503,
          recoverable: true,
        ),
      );
    }

    final Map<String, Duration> healthy = <String, Duration>{};
    await Future.wait(<Future<void>>[
      for (final LandscapeEntry entry in doc.landscapes)
        _pinger.ping(entry).then((Duration? latency) {
          if (latency != null) {
            healthy[entry.name] = latency;
          }
        }),
    ]);

    if (healthy.isEmpty) {
      return const Err<String>(
        Problem(
          type: 'urn:diene:problem:landscape-unhealthy',
          title: 'No healthy landscape found',
          status: 503,
          recoverable: true,
        ),
      );
    }

    if (preferred != null && healthy.containsKey(preferred)) {
      return Ok<String>(preferred);
    }
    final MapEntry<String, Duration> fastest = healthy.entries.reduce(
      (MapEntry<String, Duration> a, MapEntry<String, Duration> b) =>
          a.value <= b.value ? a : b,
    );
    return Ok<String>(fastest.key);
  }
}
