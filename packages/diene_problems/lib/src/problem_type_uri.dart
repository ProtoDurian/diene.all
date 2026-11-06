/// One path segment of a problem type URI.
typedef ProblemTypeSegment = String;

/// The service-tree coordinates every problem type URI is built from.
final class ErrorPortal {
  const ErrorPortal({
    required this.scheme,
    required this.host,
    required this.landscape,
    required this.platform,
    required this.service,
    required this.module,
  });

  /// URI scheme, conventionally `https`.
  final ProblemTypeSegment scheme;

  /// A bare `host` or `host:port` serving the problem docs.
  final ProblemTypeSegment host;

  final ProblemTypeSegment landscape;
  final ProblemTypeSegment platform;
  final ProblemTypeSegment service;
  final ProblemTypeSegment module;

  /// Fallback portal for client errors raised before any backend is known.
  static const ErrorPortal localError = ErrorPortal(
    scheme: 'https',
    host: 'local.atomi.cloud',
    landscape: 'local',
    platform: 'flutter',
    service: 'app',
    module: 'core',
  );
}

/// Thrown when a portal field, version or id cannot form a type URI.
class InvalidProblemTypeSegmentError extends ArgumentError {
  InvalidProblemTypeSegmentError(String name, Object? value)
    : super.value(value, name, 'is not a valid problem type URI segment');
}

/// Landscape, platform, service and module segments.
final RegExp problemSegmentPattern = RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]*$');

/// Wire problem ids: snake_case.
final RegExp problemWireIdPattern = RegExp(r'^[a-z][a-z0-9_]*$');

/// Contract versions: `v` and digits, e.g. `v1`.
final RegExp problemVersionPattern = RegExp(r'^v[0-9]+$');

final RegExp _hostForbidden = RegExp(r'[/\\\s@?#]');

void _check(String name, String value, RegExp pattern) {
  if (!pattern.hasMatch(value)) {
    throw InvalidProblemTypeSegmentError(name, value);
  }
}

/// Builds `{scheme}://{host}/docs/{landscape}/{platform}/{service}/{module}/{version}/{id}`.
///
/// This is the only formatter of the template; never build the string by hand.
String problemTypeUri({
  required ErrorPortal portal,
  required ProblemTypeSegment version,
  required ProblemTypeSegment id,
}) {
  _check('scheme', portal.scheme, problemSegmentPattern);
  final String host = portal.host;
  if (host.isEmpty ||
      _hostForbidden.hasMatch(host) ||
      Uri.tryParse('${portal.scheme}://$host/')?.authority != host) {
    throw InvalidProblemTypeSegmentError('host', host);
  }
  _check('landscape', portal.landscape, problemSegmentPattern);
  _check('platform', portal.platform, problemSegmentPattern);
  _check('service', portal.service, problemSegmentPattern);
  _check('module', portal.module, problemSegmentPattern);
  _check('version', version, problemVersionPattern);
  _check('id', id, problemWireIdPattern);
  return '${portal.scheme}://$host/docs/${portal.landscape}'
      '/${portal.platform}/${portal.service}/${portal.module}/$version/$id';
}
