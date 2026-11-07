library;

import 'package:diene_problems/diene_problems.dart';
import 'package:diene_result/diene_result.dart';

enum UtilName {
  slug,
  coercion,
  record,
  wire,
  concurrency,
  timing,
  vfs;

  String get wireId => name;
}

enum UtilErrorCode {
  invalidInput('invalid_input', 400),
  invalidFormat('invalid_format', 400),
  conflict('conflict', 409),
  unprojectable('unprojectable', 422),
  delegated('delegated', 500);

  const UtilErrorCode(this.wireId, this.status);

  final String wireId;
  final int status;

  /// Always false: these failures depend only on the input.
  bool get recoverable => false;
}

const String coreUtilsProblemVersion = 'v1';

/// Builds the `Problem` for a failure, typed `<util>_<code>` under `v1`.
Problem utilProblem({
  required UtilName util,
  required UtilErrorCode code,
  required String operation,
  required String message,
  ErrorPortal portal = ErrorPortal.localError,
  Map<String, Object?> details = const <String, Object?>{},
}) => Problem(
  type: problemTypeUri(
    portal: portal,
    version: coreUtilsProblemVersion,
    id: '${util.wireId}_${code.wireId}',
  ),
  title: message,
  status: code.status,
  detail: '${util.wireId}.$operation: $message',
  recoverable: code.recoverable,
  data: <String, Object?>{
    'util': util.wireId,
    'code': code.wireId,
    'operation': operation,
    ...details,
  },
);

Err<T> utilFailure<T>({
  required UtilName util,
  required UtilErrorCode code,
  required String operation,
  required String message,
  ErrorPortal portal = ErrorPortal.localError,
  Map<String, Object?> details = const <String, Object?>{},
}) => Err<T>(
  utilProblem(
    util: util,
    code: code,
    operation: operation,
    message: message,
    portal: portal,
    details: details,
  ),
);

Err<T> invalidUtilInput<T>({
  required UtilName util,
  required String operation,
  required String field,
  required String message,
}) => utilFailure<T>(
  util: util,
  code: UtilErrorCode.invalidInput,
  operation: operation,
  message: message,
  details: <String, Object?>{'field': field},
);

Err<T> invalidWireFormat<T>({
  required String operation,
  required String expected,
  required String value,
}) => utilFailure<T>(
  util: UtilName.wire,
  code: UtilErrorCode.invalidFormat,
  operation: operation,
  message: 'expected $expected',
  details: <String, Object?>{'expected': expected, 'value': value},
);
