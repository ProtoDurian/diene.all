import 'problem.dart';
import 'problem_type_uri.dart';
import 'registry.dart';

/// Options for [fromObject].
final class TransformOptions {
  const TransformOptions({
    this.portal = ErrorPortal.localError,
    this.registry,
    this.defaultStatus = 500,
    this.defaultVersion = 'v1',
  });

  /// Portal of the uncatalogued fallback type URI.
  final ErrorPortal portal;

  /// Resolves a `problemId` carried by a map value.
  final ProblemRegistry? registry;
  final int defaultStatus;
  final String defaultVersion;
}

/// Folds any value into a [Problem]; never throws.
///
/// A [Problem] is returned as is. A map whose `problemId` the registry knows
/// becomes that problem with the map's `data`. Anything else becomes the
/// [uncataloguedProblemId] problem.
Problem fromObject(
  Object? error, {
  TransformOptions options = const TransformOptions(),
}) {
  if (error is Problem) {
    return error;
  }
  final ProblemRegistry? registry = options.registry;
  if (registry != null && error is Map<String, Object?>) {
    final Object? id = error['problemId'];
    final ProblemType? type = id is String ? registry.lookup(id) : null;
    if (type != null) {
      final Object? data = error['data'];
      return Problem(
        type: registry.typeUriFor(type),
        title: type.title,
        status: type.status ?? options.defaultStatus,
        recoverable: type.recoverable,
        data: data is Map<Object?, Object?>
            ? data.map(
                (Object? key, Object? value) => MapEntry(key.toString(), value),
              )
            : null,
      );
    }
  }
  return Problem(
    type: problemTypeUri(
      portal: options.portal,
      version: options.defaultVersion,
      id: uncataloguedProblemId,
    ),
    title: 'Unexpected problem',
    status: options.defaultStatus,
    detail: error?.toString(),
  );
}
