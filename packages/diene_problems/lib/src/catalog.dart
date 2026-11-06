import 'problem_type_uri.dart';
import 'registry.dart';

/// An endpoint that can return a cataloged problem.
final class CatalogEndpoint {
  const CatalogEndpoint({required this.method, required this.path});

  /// Uppercase HTTP method, e.g. `POST`.
  final String method;

  /// Path starting with `/`, e.g. `/user/{id}`.
  final String path;

  Map<String, Object?> toJson() => <String, Object?>{
    'method': method,
    'path': path,
  };
}

/// One problem entry of a Problem CR.
final class CatalogEntry {
  /// [typeUri] must come from `problemTypeUri`.
  const CatalogEntry({
    required this.id,
    required this.typeUri,
    required this.title,
    required this.status,
    required this.recoverable,
    this.dataSchema,
    this.endpoints = const <CatalogEndpoint>[],
  });

  final String id;
  final String typeUri;
  final String title;
  final int status;
  final bool recoverable;

  /// JSON Schema of the `data` payload; `null` means no data.
  final Map<String, Object?>? dataSchema;
  final List<CatalogEndpoint> endpoints;

  /// The CR entry; a data-less problem publishes [noProblemDataSchema].
  Map<String, Object?> toCrdContent() => <String, Object?>{
    'id': id,
    'type': typeUri,
    'title': title,
    'status': status,
    'recoverable': recoverable,
    'schema': dataSchema ?? noProblemDataSchema,
    'endpoints': endpoints
        .map((CatalogEndpoint endpoint) => endpoint.toJson())
        .toList(growable: false),
  };
}

/// Thrown when a catalog cannot be emitted as a Problem CR.
class ProblemResourceError extends StateError {
  ProblemResourceError(super.message);
}

const Set<String> _httpMethods = <String>{
  'GET',
  'HEAD',
  'POST',
  'PUT',
  'PATCH',
  'DELETE',
  'OPTIONS',
  'TRACE',
  'CONNECT',
};

final RegExp _dnsLabel = RegExp(r'^[a-z0-9]([-a-z0-9]{0,61}[a-z0-9])?$');

/// The cataloged problems of one service, keyed by id.
final class ProblemCatalog {
  ProblemCatalog({required this.portal, List<CatalogEntry>? entries})
    : _entries = <String, CatalogEntry>{} {
    entries?.forEach(add);
  }

  final ErrorPortal portal;
  final Map<String, CatalogEntry> _entries;

  /// Adds [entry], replacing any entry with the same id.
  void add(CatalogEntry entry) => _entries[entry.id] = entry;

  /// Adds [type] with its type URI built from [portal].
  void addType(
    ProblemType type, {
    List<CatalogEndpoint> endpoints = const <CatalogEndpoint>[],
  }) => add(
    CatalogEntry(
      id: type.id,
      typeUri: problemTypeUri(
        portal: portal,
        version: type.version,
        id: type.id,
      ),
      title: type.title,
      status: type.status ?? 500,
      recoverable: type.recoverable,
      dataSchema: type.dataSchema,
      endpoints: endpoints,
    ),
  );

  /// Adds every [GenericProblems] entry.
  void addGenerics() => GenericProblems.all.forEach(addType);

  CatalogEntry? lookup(String id) => _entries[id];

  /// Entries in insertion order.
  Iterable<CatalogEntry> get entries => _entries.values;

  /// The CR `problems[]` list in insertion order.
  List<Map<String, Object?>> toCrdContent() => _entries.values
      .map((CatalogEntry entry) => entry.toCrdContent())
      .toList(growable: false);

  /// The Problem CR for the row ([portal], [version]), problems sorted by id.
  ///
  /// Throws [ProblemResourceError] when the row is invalid or an entry was
  /// not built for it.
  Map<String, Object?> toProblemResource({required String version}) {
    if (portal.scheme != 'https') {
      throw ProblemResourceError('a Problem CR needs an https portal');
    }
    final Map<String, String> identity = <String, String>{
      'platform': portal.platform,
      'service': portal.service,
      'module': portal.module,
      'landscape': portal.landscape,
    };
    identity.forEach((String field, String value) {
      if (!_dnsLabel.hasMatch(value)) {
        throw ProblemResourceError('$field "$value" is not a DNS-1123 label');
      }
    });
    if (!problemVersionPattern.hasMatch(version)) {
      throw ProblemResourceError('version "$version" is not v<n>');
    }
    final List<CatalogEntry> sorted = _entries.values.toList()
      ..sort((CatalogEntry a, CatalogEntry b) => a.id.compareTo(b.id));
    for (final CatalogEntry entry in sorted) {
      _checkEntry(entry, version);
    }
    return <String, Object?>{
      'apiVersion': 'atomi.cloud/v1alpha1',
      'kind': 'Problem',
      'metadata': <String, Object?>{
        'name': <String>[
          portal.service,
          portal.module,
          portal.landscape,
          version,
        ].join('.'),
        'namespace': portal.platform,
      },
      'spec': <String, Object?>{
        ...identity,
        'version': version,
        'problems': sorted
            .map((CatalogEntry entry) => entry.toCrdContent())
            .toList(growable: false),
      },
    };
  }

  void _checkEntry(CatalogEntry entry, String version) {
    final String expected = problemTypeUri(
      portal: portal,
      version: version,
      id: entry.id,
    );
    if (entry.typeUri != expected) {
      throw ProblemResourceError(
        'problem ${entry.typeUri} does not belong to the row $expected',
      );
    }
    final Set<String> seen = <String>{};
    for (final CatalogEndpoint endpoint in entry.endpoints) {
      final String key = '${endpoint.method} ${endpoint.path}';
      if (!_httpMethods.contains(endpoint.method) ||
          !endpoint.path.startsWith('/') ||
          !seen.add(key)) {
        throw ProblemResourceError(
          'problem ${entry.id} declares an invalid or repeated endpoint $key',
        );
      }
    }
  }
}
