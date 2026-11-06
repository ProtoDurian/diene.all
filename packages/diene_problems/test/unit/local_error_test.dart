import 'package:diene_problems/diene_problems.dart';
import 'package:test/test.dart';

final class _RecordingSink implements ErrorSink {
  Problem? captured;

  @override
  Future<void> capture(Problem problem) async => captured = problem;
}

void main() {
  group('LocalError', () {
    test('puts message and stack trace in data and captures it', () async {
      // Arrange
      const ErrorPortal portal = ErrorPortal(
        scheme: 'https',
        host: 'docs.raichu.cluster.atomi.cloud',
        landscape: 'raichu',
        platform: 'dotnet',
        service: 'user',
        module: 'api',
      );
      final _RecordingSink sink = _RecordingSink();
      final StackTrace stack = StackTrace.current;

      // Act
      final Problem problem = await LocalError(
        sink,
        portal: portal,
      ).wrap(StateError('broken'), stack);

      // Assert
      expect(problem.title, 'Local Error');
      expect(problem.status, 500);
      expect(problem.recoverable, isFalse);
      expect(problem.detail, contains('broken'));
      expect(problem.data!['message'], contains('broken'));
      expect(problem.data!['stackTrace'], stack.toString());
      expect(
        problem.type,
        'https://docs.raichu.cluster.atomi.cloud/docs/raichu/dotnet/user/api/v1/local_error',
      );
      expect(sink.captured, same(problem));
    });

    test('defaults to the local-error portal and a no-op sink', () async {
      // Arrange
      const LocalError localError = LocalError(NoopErrorSink());

      // Act
      final Problem problem = await localError.wrap('x', StackTrace.empty);

      // Assert
      expect(
        problem.type,
        'https://local.atomi.cloud/docs/local/flutter/app/core/v1/local_error',
      );
    });
  });
}
