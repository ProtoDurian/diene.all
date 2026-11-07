import 'dart:collection';

import 'package:diene_result/diene_result.dart';

import 'port_problem.dart';
import 'telemetry.dart';

enum MetricKind { counter, gauge, histogram }

final RegExp metricNamePattern = RegExp(r'^[A-Za-z][A-Za-z0-9_.\-/]{0,254}$');

final class MetricRecord {
  /// [attributes] is copied and exposed unmodifiable.
  MetricRecord({
    required this.timestamp,
    required this.name,
    required this.kind,
    required this.value,
    this.unit,
    TelemetryAttributes attributes = const <String, Object?>{},
  }) : attributes = UnmodifiableMapView<String, Object?>(
         Map<String, Object?>.of(attributes),
       );

  final DateTime timestamp;

  final String name;

  final MetricKind kind;

  final num value;

  final String? unit;

  final TelemetryAttributes attributes;

  @override
  String toString() => 'MetricRecord($name, ${kind.name}, $value)';
}

/// Receives metric samples; adapters (for example Faro in Flutter) live elsewhere.
abstract interface class MetricsCollector {
  Result<void> emit(MetricRecord record);

  Future<Result<void>> flush();
}

/// Requires a valid name, UTC timestamp, finite value (non-negative for
/// counters), no blank unit and valid attributes.
Result<MetricRecord> checkMetricRecord(
  MetricRecord record, {
  String operation = 'emit',
}) {
  if (!metricNamePattern.hasMatch(record.name)) {
    return invalidInput<MetricRecord>(
      port: PortName.metrics,
      operation: operation,
      field: 'name',
      message: 'Metric name must match $metricNamePattern',
    );
  }
  if (!record.timestamp.isUtc) {
    return invalidInput<MetricRecord>(
      port: PortName.metrics,
      operation: operation,
      field: 'timestamp',
      message: 'Metric timestamp must be UTC',
    );
  }
  if (!record.value.isFinite) {
    return invalidInput<MetricRecord>(
      port: PortName.metrics,
      operation: operation,
      field: 'value',
      message: 'Metric value must be finite',
    );
  }
  if (record.kind == MetricKind.counter && record.value < 0) {
    return invalidInput<MetricRecord>(
      port: PortName.metrics,
      operation: operation,
      field: 'value',
      message: 'Counter samples must not be negative',
    );
  }
  final String? unit = record.unit;
  if (unit != null && unit.trim().isEmpty) {
    return invalidInput<MetricRecord>(
      port: PortName.metrics,
      operation: operation,
      field: 'unit',
      message: 'Unit must be omitted rather than blank',
    );
  }
  return checkTelemetryAttributes(
    record.attributes,
    port: PortName.metrics,
    operation: operation,
  ).map((TelemetryAttributes _) => record);
}
