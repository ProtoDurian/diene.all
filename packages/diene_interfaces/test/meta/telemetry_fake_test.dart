import 'package:diene_interfaces/diene_interfaces.dart';
import 'package:diene_interfaces/test_helper.dart';
import 'package:diene_result/test_helper.dart';
import 'package:test/test.dart';

LogRecord _log([LogLevel level = LogLevel.info]) => LogRecord(
  timestamp: DateTime.utc(2026, 7, 25),
  level: level,
  message: 'event',
);

MetricRecord _metric([num value = 1]) => MetricRecord(
  timestamp: DateTime.utc(2026, 7, 25),
  name: 'requests.total',
  kind: MetricKind.counter,
  value: value,
);

void main() {
  group('InMemoryLoggerSink', () {
    test('captures emitted records in call order', () {
      // Arrange
      final InMemoryLoggerSink sink = InMemoryLoggerSink();

      // Act
      final first = sink.emit(_log());
      final second = sink.emit(_log(LogLevel.error));

      // Assert
      expectOk(first);
      expectOk(second);
      expect(sink.records.map((LogRecord record) => record.level), <LogLevel>[
        LogLevel.info,
        LogLevel.error,
      ]);
    });

    test('a scripted failure crosses as a value and is not captured', () {
      // Arrange
      final InMemoryLoggerSink sink = InMemoryLoggerSink()
        ..enqueue(
          portFailure<void>(
            port: PortName.logging,
            code: PortErrorCode.io,
            operation: 'emit',
            message: 'Sink write failed',
          ),
        );

      // Act
      final rejected = sink.emit(_log());
      final List<LogRecord> recordsAfterFailure = List<LogRecord>.of(
        sink.records,
      );
      final accepted = sink.emit(_log());

      // Assert
      expectPortProblem(
        expectErr(rejected),
        port: PortName.logging,
        code: PortErrorCode.io,
      );
      expect(
        recordsAfterFailure,
        isEmpty,
        reason: 'a rejected record is not stored',
      );
      expectOk(accepted);
      expect(sink.records, hasLength(1));
    });

    test('counts flushes and honours a scripted flush failure', () async {
      // Arrange
      final InMemoryLoggerSink sink = InMemoryLoggerSink()
        ..enqueueFlushResult(
          portFailure<void>(
            port: PortName.logging,
            code: PortErrorCode.unavailable,
            operation: 'flush',
            message: 'Sink unavailable',
          ),
        );

      // Act
      final rejected = await sink.flush();
      final accepted = await sink.flush();

      // Assert
      expectPortProblem(
        expectErr(rejected),
        port: PortName.logging,
        code: PortErrorCode.unavailable,
      );
      expectOk(accepted);
      expect(sink.flushCount, 2);
    });
  });

  group('InMemoryMetricsCollector', () {
    test('captures emitted samples in call order', () {
      // Arrange
      final InMemoryMetricsCollector collector = InMemoryMetricsCollector();

      // Act
      final first = collector.emit(_metric());
      final second = collector.emit(_metric(4));

      // Assert
      expectOk(first);
      expectOk(second);
      expect(
        collector.records.map((MetricRecord record) => record.value),
        <num>[1, 4],
      );
    });

    test('a scripted failure crosses as a value and is not captured', () {
      // Arrange
      final InMemoryMetricsCollector collector = InMemoryMetricsCollector()
        ..enqueue(
          portFailure<void>(
            port: PortName.metrics,
            code: PortErrorCode.io,
            operation: 'emit',
            message: 'Registry write failed',
          ),
        );

      // Act
      final rejected = collector.emit(_metric());
      final List<MetricRecord> recordsAfterFailure = List<MetricRecord>.of(
        collector.records,
      );
      final accepted = collector.emit(_metric());

      // Assert
      expectPortProblem(
        expectErr(rejected),
        port: PortName.metrics,
        code: PortErrorCode.io,
      );
      expect(recordsAfterFailure, isEmpty);
      expectOk(accepted);
      expect(collector.records, hasLength(1));
    });

    test('counts flushes and honours a scripted flush failure', () async {
      // Arrange
      final InMemoryMetricsCollector collector = InMemoryMetricsCollector()
        ..enqueueFlushResult(
          portFailure<void>(
            port: PortName.metrics,
            code: PortErrorCode.timeout,
            operation: 'flush',
            message: 'Flush timed out',
          ),
        );

      // Act
      final rejected = await collector.flush();
      final accepted = await collector.flush();

      // Assert
      expectPortProblem(
        expectErr(rejected),
        port: PortName.metrics,
        code: PortErrorCode.timeout,
      );
      expectOk(accepted);
      expect(collector.flushCount, 2);
    });
  });
}
