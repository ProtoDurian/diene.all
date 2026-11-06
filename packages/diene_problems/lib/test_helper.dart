/// Framework-free Problem matcher and builders for consumer tests.
///
/// A failed match throws [ProblemMatcherError]; no test package is imported.
library;

import 'diene_problems.dart';

/// Thrown by [expectProblem] on a mismatch.
final class ProblemMatcherError extends AssertionError {
  ProblemMatcherError(super.message);
}

void _expectField(String field, Object? expected, Object? actual) {
  if (!_deepEquals(expected, actual)) {
    throw ProblemMatcherError(
      'Problem.$field mismatch: expected <$expected> got <$actual>',
    );
  }
}

bool _deepEquals(Object? a, Object? b) {
  if (a is Map<Object?, Object?> && b is Map<Object?, Object?>) {
    return a.length == b.length &&
        a.keys.every(
          (Object? key) => b.containsKey(key) && _deepEquals(a[key], b[key]),
        );
  }
  if (a is List<Object?> && b is List<Object?>) {
    if (a.length != b.length) {
      return false;
    }
    for (int i = 0; i < a.length; i++) {
      if (!_deepEquals(a[i], b[i])) {
        return false;
      }
    }
    return true;
  }
  return a == b;
}

/// Asserts [actual] is a [Problem] whose given fields match.
///
/// Omitted fields are not checked; [noData] asserts the problem has no data.
void expectProblem(
  Object? actual, {
  String? type,
  String? title,
  int? status,
  bool? recoverable,
  String? detail,
  String? instance,
  Map<String, Object?>? data,
  bool noData = false,
}) {
  if (actual is! Problem) {
    throw ProblemMatcherError(
      'expected a Problem but got ${actual.runtimeType}',
    );
  }
  final Map<String, Object?> expected = <String, Object?>{
    'type': type,
    'title': title,
    'status': status,
    'recoverable': recoverable,
    'detail': detail,
    'instance': instance,
    'data': data,
  };
  final Map<String, Object?> found = <String, Object?>{
    'type': actual.type,
    'title': actual.title,
    'status': actual.status,
    'recoverable': actual.recoverable,
    'detail': actual.detail,
    'instance': actual.instance,
    'data': actual.data,
  };
  expected.forEach((String field, Object? value) {
    if (value != null) {
      _expectField(field, value, found[field]);
    }
  });
  if (noData) {
    _expectField('data', null, actual.data);
  }
}

const Map<String, Object?> _entityReference = <String, Object?>{
  'entityType': 'user',
  'id': '42',
};

/// Builds a valid `entity_not_found` [Problem]; pass `data: null` for none.
Problem aProblem({
  ErrorPortal portal = ErrorPortal.localError,
  String id = 'entity_not_found',
  String version = 'v1',
  String title = 'Entity not found',
  int status = 404,
  bool recoverable = false,
  String? detail,
  String? instance,
  Map<String, Object?>? data = _entityReference,
}) => Problem(
  type: problemTypeUri(portal: portal, version: version, id: id),
  title: title,
  status: status,
  detail: detail,
  instance: instance,
  recoverable: recoverable,
  data: data,
);

/// Builds a valid [ErrorPortal].
ErrorPortal anErrorPortal({
  String scheme = 'https',
  String host = 'docs.raichu.cluster.atomi.cloud',
  String landscape = 'raichu',
  String platform = 'dotnet',
  String service = 'user',
  String module = 'api',
}) => ErrorPortal(
  scheme: scheme,
  host: host,
  landscape: landscape,
  platform: platform,
  service: service,
  module: module,
);

/// Builds a [CatalogEntry] whose type URI comes from `problemTypeUri`.
CatalogEntry aCatalogEntry({
  ErrorPortal portal = ErrorPortal.localError,
  required String id,
  String version = 'v1',
  String title = 'Entity not found',
  int status = 404,
  bool recoverable = false,
  Map<String, Object?>? dataSchema,
  List<CatalogEndpoint> endpoints = const <CatalogEndpoint>[],
}) => CatalogEntry(
  id: id,
  typeUri: problemTypeUri(portal: portal, version: version, id: id),
  title: title,
  status: status,
  recoverable: recoverable,
  dataSchema: dataSchema,
  endpoints: endpoints,
);
