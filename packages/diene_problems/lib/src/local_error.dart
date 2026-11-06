import 'problem.dart';
import 'problem_type_uri.dart';

/// Receives the problems [LocalError] captures.
abstract interface class ErrorSink {
  Future<void> capture(Problem problem);
}

/// An [ErrorSink] that discards every capture.
final class NoopErrorSink implements ErrorSink {
  const NoopErrorSink();

  @override
  Future<void> capture(Problem problem) async {}
}

/// Wraps unexpected client exceptions into a `local_error` Problem.
final class LocalError {
  const LocalError(this.sink, {this.portal = ErrorPortal.localError});

  final ErrorSink sink;
  final ErrorPortal portal;

  /// Builds the Problem with the message and stack trace in `data`, captures
  /// it on [sink] and returns it.
  Future<Problem> wrap(Object error, StackTrace stackTrace) async {
    final String message = error.toString();
    final Problem problem = Problem(
      type: problemTypeUri(portal: portal, version: 'v1', id: 'local_error'),
      title: 'Local Error',
      status: 500,
      detail: message,
      data: <String, Object?>{
        'message': message,
        'stackTrace': stackTrace.toString(),
      },
    );
    await sink.capture(problem);
    return problem;
  }
}
