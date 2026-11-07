import 'dart:collection';

import 'package:diene_result/diene_result.dart';

import 'port_problem.dart';

typedef TelemetryAttributes = Map<String, Object?>;

final TelemetryAttributes emptyTelemetryAttributes =
    UnmodifiableMapView<String, Object?>(const <String, Object?>{});

/// Allows non-blank, NUL-free keys and finite `num`, `bool` or `String`
/// values; returns a key-sorted unmodifiable copy (`null` is the empty bag).
Result<TelemetryAttributes> checkTelemetryAttributes(
  TelemetryAttributes? attributes, {
  required PortName port,
  required String operation,
}) {
  if (attributes == null || attributes.isEmpty) {
    return Ok<TelemetryAttributes>(emptyTelemetryAttributes);
  }
  for (final MapEntry<String, Object?> entry in attributes.entries) {
    if (entry.key.trim().isEmpty || entry.key.codeUnits.contains(0)) {
      return invalidInput<TelemetryAttributes>(
        port: port,
        operation: operation,
        field: 'attributes',
        message: 'Telemetry attribute names must be non-blank and NUL-free',
      );
    }
    final Object? value = entry.value;
    final bool finitePrimitive =
        value is bool || value is String || (value is num && value.isFinite);
    if (!finitePrimitive) {
      return invalidInput<TelemetryAttributes>(
        port: port,
        operation: operation,
        field: 'attributes.${entry.key}',
        message: 'Telemetry attribute values must be finite primitives',
      );
    }
  }
  final List<String> keys = attributes.keys.toList()..sort();
  return Ok<TelemetryAttributes>(
    UnmodifiableMapView<String, Object?>(<String, Object?>{
      for (final String key in keys) key: attributes[key],
    }),
  );
}
