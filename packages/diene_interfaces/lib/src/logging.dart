import 'dart:collection';

import 'package:diene_result/diene_result.dart';

import 'port_problem.dart';
import 'telemetry.dart';

enum LogLevel { trace, debug, info, warning, error, fatal }

final class LogRecord {
  /// [attributes] is copied and exposed unmodifiable.
  LogRecord({
    required this.timestamp,
    required this.level,
    required this.message,
    TelemetryAttributes attributes = const <String, Object?>{},
    this.error,
    this.stackTrace,
  }) : attributes = UnmodifiableMapView<String, Object?>(
         Map<String, Object?>.of(attributes),
       );

  final DateTime timestamp;

  final LogLevel level;

  final String message;

  final TelemetryAttributes attributes;

  final String? error;

  final String? stackTrace;

  @override
  String toString() => 'LogRecord(${level.name}, $message)';
}

/// Receives structured logs; adapters (for example Faro in Flutter) live elsewhere.
abstract interface class LoggerSink {
  Result<void> emit(LogRecord record);

  Future<Result<void>> flush();
}

/// Requires a non-blank message, a UTC timestamp and valid attributes.
Result<LogRecord> checkLogRecord(
  LogRecord record, {
  String operation = 'emit',
}) {
  if (record.message.trim().isEmpty) {
    return invalidInput<LogRecord>(
      port: PortName.logging,
      operation: operation,
      field: 'message',
      message: 'Log message must be non-blank',
    );
  }
  if (!record.timestamp.isUtc) {
    return invalidInput<LogRecord>(
      port: PortName.logging,
      operation: operation,
      field: 'timestamp',
      message: 'Log timestamp must be UTC',
    );
  }
  return checkTelemetryAttributes(
    record.attributes,
    port: PortName.logging,
    operation: operation,
  ).map((TelemetryAttributes _) => record);
}
