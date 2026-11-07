import 'package:diene_interfaces/diene_interfaces.dart';
import 'package:diene_interfaces/test_helper.dart';
import 'package:diene_result/diene_result.dart';
import 'package:diene_result/test_helper.dart';
import 'package:test/test.dart';

void main() {
  group('InMemorySystem defaults', () {
    test('answers from its seeded environment, directory, and clock', () {
      // Arrange
      final InMemorySystem system = InMemorySystem(
        environment: <String, String>{'HOME': '/home/dev'},
        directory: '/work',
        now: DateTime.utc(2026, 7, 25, 6, 30),
      );

      // Act
      final homeResult = system.environment('HOME');
      final absentResult = system.environment('MISSING');
      final directoryResult = system.currentDirectory();
      final clockResult = system.nowUtc();

      // Assert
      expect(expectOk(homeResult), '/home/dev');
      expect(
        expectOk(absentResult),
        isNull,
        reason: 'absence is Ok(null), not a failure',
      );
      expect(expectOk(directoryResult), '/work');
      final DateTime now = expectOk(clockResult);
      expect(now, DateTime.utc(2026, 7, 25, 6, 30));
      expect(now.isUtc, isTrue);
    });

    test('uses the epoch and root when unseeded', () {
      // Arrange
      final InMemorySystem system = InMemorySystem();

      // Act
      final directoryResult = system.currentDirectory();
      final clockResult = system.nowUtc();

      // Assert
      expect(expectOk(directoryResult), '/');
      expect(
        expectOk(clockResult),
        DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      );
    });

    test('normalises a local seed instant to UTC', () {
      // Arrange
      final DateTime now = DateTime(2026, 7, 25);

      // Act
      final InMemorySystem system = InMemorySystem(now: now);
      final result = system.nowUtc();

      // Assert
      expect(expectOk(result).isUtc, isTrue);
    });

    test('records every requested delay and succeeds by default', () async {
      // Arrange
      final InMemorySystem system = InMemorySystem();

      // Act
      final first = await system.delay(const Duration(milliseconds: 5));
      final second = await system.delay(const Duration(seconds: 1));

      // Assert
      expectOk(first);
      expectOk(second);
      expect(system.requestedDelays, <Duration>[
        const Duration(milliseconds: 5),
        const Duration(seconds: 1),
      ]);
    });

    test('exposes its environment and directory as mutable seams', () {
      // Arrange
      final InMemorySystem system = InMemorySystem();

      // Act
      system.environmentVariables['ADDED'] = 'yes';
      system.directory = '/moved';
      system.now = DateTime.utc(2030);
      final environmentResult = system.environment('ADDED');
      final directoryResult = system.currentDirectory();
      final clockResult = system.nowUtc();

      // Assert
      expect(expectOk(environmentResult), 'yes');
      expect(expectOk(directoryResult), '/moved');
      expect(expectOk(clockResult), DateTime.utc(2030));
    });
  });

  group('InMemorySystem scripted results', () {
    test('serves scripted answers FIFO, then falls back to state', () {
      // Arrange
      final InMemorySystem system = InMemorySystem(
        environment: <String, String>{'HOME': '/fallback'},
      )..enqueueEnvironmentResult(const Ok<String?>('/scripted'));
      system.enqueueEnvironmentResult(
        portFailure<String?>(
          port: PortName.system,
          code: PortErrorCode.permissionDenied,
          operation: 'environment',
          message: 'Environment unreadable',
        ),
      );

      // Act
      final first = system.environment('HOME');
      final second = system.environment('HOME');
      final third = system.environment('HOME');

      // Assert
      expect(expectOk(first), '/scripted');
      expect(expectErr(second), isNotNull);
      expect(expectOk(third), '/fallback');
    });

    test('scripts directory, clock, and delay failures', () async {
      // Arrange
      final InMemorySystem system = InMemorySystem()
        ..enqueueDirectoryResult(
          portFailure<String>(
            port: PortName.system,
            code: PortErrorCode.io,
            operation: 'currentDirectory',
            message: 'Directory unavailable',
          ),
        )
        ..enqueueClockResult(
          portFailure<DateTime>(
            port: PortName.system,
            code: PortErrorCode.unavailable,
            operation: 'nowUtc',
            message: 'Clock unavailable',
          ),
        )
        ..enqueueDelayResult(
          portFailure<void>(
            port: PortName.system,
            code: PortErrorCode.timeout,
            operation: 'delay',
            message: 'Timer failed',
          ),
        );

      // Act
      final directoryResult = system.currentDirectory();
      final clockResult = system.nowUtc();
      final delayResult = await system.delay(Duration.zero);

      // Assert
      expectPortProblem(
        expectErr(directoryResult),
        port: PortName.system,
        code: PortErrorCode.io,
      );
      expectPortProblem(
        expectErr(clockResult),
        port: PortName.system,
        code: PortErrorCode.unavailable,
      );
      expectPortProblem(
        expectErr(delayResult),
        port: PortName.system,
        code: PortErrorCode.timeout,
      );
      expect(system.requestedDelays, hasLength(1));
    });
  });
}
