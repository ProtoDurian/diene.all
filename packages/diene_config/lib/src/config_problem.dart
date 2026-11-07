import 'package:diene_problems/diene_problems.dart';
import 'package:diene_result/diene_result.dart';

/// Version segment of every config problem type URI.
const String configProblemVersion = 'v1';

/// How a `diene_config` operation failed.
enum ConfigProblemCode {
  sourceUnreadable('source_unreadable', 422),

  sourceNotAMap('source_not_a_map', 422),

  /// The final merged configuration failed validation.
  schemaInvalid('schema_invalid', 422),

  landscapeMissing('landscape_missing', 400);

  const ConfigProblemCode(this.wireId, this.status);

  final String wireId;

  final int status;
}

/// Reserved `data` key carrying the code's [ConfigProblemCode.wireId].
const String configProblemCodeKey = 'code';

/// Reserved `data` key marking an envelope minted by [configProblem].
const String configProblemProvenanceKey = 'x-diene-config-provenance';

const String configProblemValue =
    'atomicloud/diene_config@$configProblemVersion';

/// Throws [ArgumentError] when [details] sets a reserved key.
Problem configProblem({
  required ConfigProblemCode code,
  required String message,
  ErrorPortal portal = ErrorPortal.localError,
  Map<String, Object?> details = const <String, Object?>{},
}) {
  const List<String> reserved = <String>[
    configProblemCodeKey,
    configProblemProvenanceKey,
  ];
  for (final String key in reserved) {
    if (details.containsKey(key)) {
      throw ArgumentError.value(
        details,
        'details',
        'must not set the reserved "$key" key — configProblem mints it '
            '(code ${code.wireId}) so provenance stays authenticated',
      );
    }
  }
  return Problem(
    type: problemTypeUri(
      portal: portal,
      version: configProblemVersion,
      id: code.wireId,
    ),
    title: message,
    status: code.status,
    detail: 'config.${code.wireId}: $message',
    data: <String, Object?>{
      ...details,
      configProblemCodeKey: code.wireId,
      configProblemProvenanceKey: configProblemValue,
    },
  );
}

/// An `Err` carrying [configProblem].
Err<T> configFailure<T>({
  required ConfigProblemCode code,
  required String message,
  ErrorPortal portal = ErrorPortal.localError,
  Map<String, Object?> details = const <String, Object?>{},
}) => Err<T>(
  configProblem(code: code, message: message, portal: portal, details: details),
);

/// The code of an envelope this package minted, or `None` for any other.
Option<ConfigProblemCode> configProblemCode(Problem problem) {
  if (problem.data[configProblemProvenanceKey] != configProblemValue) {
    return const None<ConfigProblemCode>();
  }
  final Object? code = problem.data[configProblemCodeKey];
  for (final ConfigProblemCode candidate in ConfigProblemCode.values) {
    if (candidate.wireId == code) {
      return Some<ConfigProblemCode>(candidate);
    }
  }
  return const None<ConfigProblemCode>();
}
