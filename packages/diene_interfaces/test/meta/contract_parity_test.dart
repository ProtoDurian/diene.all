// No real adapter ships here; fakes and downstream adapters run this suite.

import 'package:diene_interfaces/diene_interfaces.dart';
import 'package:diene_interfaces/test_helper.dart';
import 'package:diene_result/diene_result.dart';
import 'package:diene_result/test_helper.dart';
import 'package:test/test.dart';

void systemContract(String label, System Function() build) {
  group('System contract ($label)', () {
    test('an absent variable is Ok(null), never a failure', () {
      // Arrange
      final System system = build();

      // Act
      final result = system.environment('__DIENE_ABSENT__');

      // Assert
      expect(expectOk(result), isNull);
    });

    test('the clock always answers in UTC', () {
      // Arrange
      final System system = build();

      // Act
      final result = system.nowUtc();

      // Assert
      expect(expectOk(result).isUtc, isTrue);
    });

    test('the working directory is absolute', () {
      // Arrange
      final System system = build();

      // Act
      final result = system.currentDirectory();

      // Assert
      expect(expectOk(result), startsWith('/'));
    });

    test('a zero delay completes', () async {
      // Arrange
      final System system = build();

      // Act
      final result = await system.delay(Duration.zero);

      // Assert
      expectOk(result);
    });
  });
}

void vfsContract(String label, Vfs Function() build) {
  group('Vfs contract ($label)', () {
    test('a missing path is a not-found VALUE, never a throw', () async {
      // Arrange
      final Vfs vfs = build();

      // Act
      final result = await vfs.readText('/__diene_absent__');

      // Assert
      expectPortProblem(
        expectErr(result),
        port: PortName.vfs,
        code: PortErrorCode.notFound,
      );
    });

    test(
      'exists answers false for a missing path rather than failing',
      () async {
        // Arrange
        final Vfs vfs = build();

        // Act
        final result = await vfs.exists('/__diene_absent__');

        // Assert
        expect(expectOk(result), isFalse);
      },
    );

    test('a written file reads back byte-identically', () async {
      // Arrange
      final Vfs vfs = build();

      // Act
      final writeResult = await vfs.writeText('/parity.txt', 'round trip');
      final readResult = await vfs.readText('/parity.txt');
      final statResult = await vfs.stat('/parity.txt');

      // Assert
      expectOk(writeResult);
      expect(expectOk(readResult), 'round trip');
      expect(expectOk(statResult).type, VfsEntryType.file);
    });

    test('a directory created recursively becomes listable', () async {
      // Arrange
      final Vfs vfs = build();

      // Act
      final createResult = await vfs.createDirectory(
        '/deep/tree',
        recursive: true,
      );
      final listResult = await vfs.list('/deep');

      // Assert
      expectOk(createResult);
      expect(expectOk(listResult), hasLength(1));
    });
  });
}

void terminalContract(String label, Terminal Function() build) {
  group('Terminal contract ($label)', () {
    test(
      'a non-zero exit is captured output, not a transport failure',
      () async {
        // Arrange
        final Terminal terminal = build();

        // Act
        final Result<TerminalOutput> result = await terminal.run(
          TerminalCommand(executable: '__diene_nonzero__'),
        );

        // Assert
        expect(expectOk(result).succeeded, isFalse);
      },
    );

    test('a write succeeds on both channels', () async {
      // Arrange
      final Terminal terminal = build();

      // Act
      final List<Result<void>> results = <Result<void>>[];
      for (final TerminalChannel channel in TerminalChannel.values) {
        results.add(
          await terminal.write(TerminalWrite(channel: channel, text: 'parity')),
        );
      }

      // Assert
      for (final Result<void> result in results) {
        expectOk(result);
      }
    });

    test('reading past the end of input is Ok(null)', () async {
      // Arrange
      final Terminal terminal = build();

      // Act
      final result = await terminal.readLine();

      // Assert
      expect(expectOk(result), isNull);
    });
  });
}

void loggerContract(String label, LoggerSink Function() build) {
  group('LoggerSink contract ($label)', () {
    test('a valid record is accepted and flushing succeeds', () async {
      // Arrange
      final LoggerSink sink = build();
      final LogRecord record = LogRecord(
        timestamp: DateTime.utc(2026),
        level: LogLevel.info,
        message: 'parity',
      );

      // Act
      final emitResult = sink.emit(record);
      final flushResult = await sink.flush();

      // Assert
      expectOk(emitResult);
      expectOk(flushResult);
    });
  });
}

void metricsContract(String label, MetricsCollector Function() build) {
  group('MetricsCollector contract ($label)', () {
    test('a valid sample is accepted and flushing succeeds', () async {
      // Arrange
      final MetricsCollector collector = build();
      final MetricRecord record = MetricRecord(
        timestamp: DateTime.utc(2026),
        name: 'parity.total',
        kind: MetricKind.counter,
        value: 1,
      );

      // Act
      final emitResult = collector.emit(record);
      final flushResult = await collector.flush();

      // Assert
      expectOk(emitResult);
      expectOk(flushResult);
    });
  });
}

void main() {
  systemContract('InMemorySystem', InMemorySystem.new);
  vfsContract('InMemoryVfs', InMemoryVfs.new);
  terminalContract(
    'InMemoryTerminal',
    () => InMemoryTerminal()
      ..enqueue(
        const Ok<TerminalOutput>(
          TerminalOutput(exitCode: 1, stdout: '', stderr: 'nonzero'),
        ),
      ),
  );
  loggerContract('InMemoryLoggerSink', InMemoryLoggerSink.new);
  metricsContract('InMemoryMetricsCollector', InMemoryMetricsCollector.new);
}
