import 'package:diene_problems/diene_problems.dart';
import 'package:diene_result/diene_result.dart';

/// Which port failed.
enum PortName { system, vfs, terminal, logging, metrics }

/// How a port failed: the snake_case wire id, HTTP status and retry hint.
enum PortErrorCode {
  alreadyExists('already_exists', 409),
  closed('closed', 409),
  directoryNotEmpty('directory_not_empty', 409),
  invalidInput('invalid_input', 400),
  io('io', 500),
  notADirectory('not_a_directory', 400),
  notAFile('not_a_file', 400),
  notFound('not_found', 404),
  permissionDenied('permission_denied', 403),
  timeout('timeout', 504, recoverable: true),
  unavailable('unavailable', 503, recoverable: true),

  /// A fake was called without a scripted response.
  unexpectedCall('unexpected_call', 500),
  unsupported('unsupported', 501);

  const PortErrorCode(this.wireId, this.status, {this.recoverable = false});

  final String wireId;

  final int status;

  final bool recoverable;
}

/// Version segment of every type URI minted here; bumping it mints new types.
const String interfacesProblemVersion = 'v1';

/// The `Problem` for a port failure; `type` ends in `<port>_<wireId>`.
Problem portProblem({
  required PortName port,
  required PortErrorCode code,
  required String operation,
  required String message,
  ErrorPortal portal = ErrorPortal.localError,
  Map<String, Object?> details = const <String, Object?>{},
}) => Problem(
  type: problemTypeUri(
    portal: portal,
    version: interfacesProblemVersion,
    id: '${port.name}_${code.wireId}',
  ),
  title: message,
  status: code.status,
  detail: '${port.name}.$operation: $message',
  recoverable: code.recoverable,
  data: <String, Object?>{
    'port': port.name,
    'code': code.wireId,
    'operation': operation,
    ...details,
  },
);

Err<T> portFailure<T>({
  required PortName port,
  required PortErrorCode code,
  required String operation,
  required String message,
  ErrorPortal portal = ErrorPortal.localError,
  Map<String, Object?> details = const <String, Object?>{},
}) => Err<T>(
  portProblem(
    port: port,
    code: code,
    operation: operation,
    message: message,
    portal: portal,
    details: details,
  ),
);

Err<T> invalidInput<T>({
  required PortName port,
  required String operation,
  required String field,
  required String message,
}) => portFailure<T>(
  port: port,
  code: PortErrorCode.invalidInput,
  operation: operation,
  message: message,
  details: <String, Object?>{'field': field},
);
