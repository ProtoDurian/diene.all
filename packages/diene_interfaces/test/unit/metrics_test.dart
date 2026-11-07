import 'package:diene_interfaces/diene_interfaces.dart';
import 'package:diene_problems/diene_problems.dart';
import 'package:diene_result/test_helper.dart';
import 'package:test/test.dart';

MetricRecord _sample({
  String name = 'requests.total',
  MetricKind kind = MetricKind.counter,
  num value = 1,
  String? unit,
  DateTime? timestamp,
  Map<String, Object?> attributes = const <String, Object?>{},
}) => MetricRecord(
  timestamp: timestamp ?? DateTime.utc(2026),
  name: name,
  kind: kind,
  value: value,
  unit: unit,
  attributes: attributes,
);

void main() {
  group('MetricRecord', () {
    test('copies and freezes its attributes', () {
      // Arrange
      final Map<String, Object?> attributes = <String, Object?>{'route': '/a'};

      // Act
      final MetricRecord record = _sample(
        name: 'latency',
        kind: MetricKind.histogram,
        value: 12.5,
        unit: 'ms',
        attributes: attributes,
      );
      attributes['injected'] = true;
      void mutate() => record.attributes.remove('route');

      // Assert
      expect(record.attributes, <String, Object?>{'route': '/a'});
      expect(mutate, throwsUnsupportedError);
      expect(record.unit, 'ms');
      expect(record.toString(), 'MetricRecord(latency, histogram, 12.5)');
      expect(MetricKind.values, hasLength(3));
    });

    test('defaults to no unit and no attributes', () {
      // Arrange
      const String name = 'requests.total';

      // Act
      final MetricRecord record = _sample(name: name);

      // Assert
      expect(record.unit, isNull);
      expect(record.attributes, isEmpty);
      expect(record.timestamp, DateTime.utc(2026));
    });
  });

  group('checkMetricRecord', () {
    test('accepts a well-formed counter sample', () {
      // Arrange
      final MetricRecord record = _sample(
        attributes: <String, Object?>{'ok': true},
      );

      // Act
      final result = checkMetricRecord(record);

      // Assert
      expect(expectOk(result), same(record));
    });

    test('accepts a negative gauge', () {
      // Arrange
      final MetricRecord record = _sample(
        name: 'queue.depth',
        kind: MetricKind.gauge,
        value: -3,
      );

      // Act
      final result = checkMetricRecord(record);

      // Assert
      expect(expectOk(result).value, -3);
    });

    test('rejects a name that breaks the shared pattern', () {
      // Arrange
      final MetricRecord record = _sample(name: '1bad');

      // Act
      final result = checkMetricRecord(record);

      // Assert
      final Problem problem = expectErr(result);
      expect(problem.data['field'], 'name');
      expect(problem.data['port'], 'metrics');
    });

    test('rejects a non-UTC timestamp', () {
      // Arrange
      final MetricRecord record = _sample(timestamp: DateTime(2026, 7, 25));

      // Act
      final result = checkMetricRecord(record);

      // Assert
      final Problem problem = expectErr(result);
      expect(problem.data['field'], 'timestamp');
    });

    test('rejects a non-finite value', () {
      // Arrange
      final MetricRecord record = _sample(
        kind: MetricKind.gauge,
        value: double.infinity,
      );

      // Act
      final result = checkMetricRecord(record);

      // Assert
      final Problem problem = expectErr(result);
      expect(problem.title, 'Metric value must be finite');
    });

    test('rejects a negative counter', () {
      // Arrange
      final MetricRecord record = _sample(value: -1);

      // Act
      final result = checkMetricRecord(record);

      // Assert
      final Problem problem = expectErr(result);
      expect(problem.title, 'Counter samples must not be negative');
    });

    test('rejects a blank unit', () {
      // Arrange
      final MetricRecord record = _sample(unit: ' ');

      // Act
      final result = checkMetricRecord(record);

      // Assert
      final Problem problem = expectErr(result);
      expect(problem.data['field'], 'unit');
    });

    test('rejects invalid attributes through the shared telemetry rule', () {
      // Arrange
      final MetricRecord record = _sample(
        attributes: <String, Object?>{'bad': Object()},
      );

      // Act
      final result = checkMetricRecord(record);

      // Assert
      final Problem problem = expectErr(result);
      expect(problem.data['field'], 'attributes.bad');
    });
  });

  test('metricNamePattern accepts the documented shape', () {
    // Arrange
    const String valid = 'http.server/duration-ms';
    const String invalid = 'has space';

    // Act
    final bool validMatches = metricNamePattern.hasMatch(valid);
    final bool invalidMatches = metricNamePattern.hasMatch(invalid);

    // Assert
    expect(validMatches, isTrue);
    expect(invalidMatches, isFalse);
  });
}
