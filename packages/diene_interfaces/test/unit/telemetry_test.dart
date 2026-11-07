import 'package:diene_interfaces/diene_interfaces.dart';
import 'package:diene_problems/diene_problems.dart';
import 'package:diene_result/diene_result.dart';
import 'package:diene_result/test_helper.dart';
import 'package:test/test.dart';

Result<TelemetryAttributes> _check(TelemetryAttributes? attributes) =>
    checkTelemetryAttributes(
      attributes,
      port: PortName.logging,
      operation: 'emit',
    );

void main() {
  group('checkTelemetryAttributes', () {
    test('treats a null bag as the empty bag', () {
      // Arrange
      const TelemetryAttributes? attributes = null;

      // Act
      final result = checkTelemetryAttributes(
        attributes,
        port: PortName.metrics,
        operation: 'emit',
      );
      void mutate() => expectOk(result)['x'] = 1;

      // Assert
      final TelemetryAttributes accepted = expectOk(result);
      expect(accepted, isEmpty);
      expect(mutate, throwsUnsupportedError);
    });

    test('treats an empty bag as the empty bag', () {
      // Arrange
      const TelemetryAttributes attributes = <String, Object?>{};

      // Act
      final result = checkTelemetryAttributes(
        attributes,
        port: PortName.metrics,
        operation: 'emit',
      );

      // Assert
      expect(expectOk(result), isEmpty);
    });

    test('accepts finite primitives and key-sorts the result', () {
      // Arrange
      final TelemetryAttributes input = <String, Object?>{
        'zebra': 'z',
        'alpha': 1,
        'mid': true,
        'ratio': 1.5,
      };

      // Act
      final result = checkTelemetryAttributes(
        input,
        port: PortName.logging,
        operation: 'emit',
      );
      void clear() => expectOk(result).clear();

      // Assert
      final TelemetryAttributes accepted = expectOk(result);
      expect(accepted.keys, <String>['alpha', 'mid', 'ratio', 'zebra']);
      expect(clear, throwsUnsupportedError);
    });

    test('rejects a blank key', () {
      // Arrange
      final TelemetryAttributes attributes = const <String, Object?>{'  ': 1};

      // Act
      final result = checkTelemetryAttributes(
        attributes,
        port: PortName.logging,
        operation: 'emit',
      );

      // Assert
      final Problem problem = expectErr(result);
      expect(problem.data['field'], 'attributes');
      expect(problem.status, 400);
    });

    test('rejects a NUL-bearing key', () {
      // Arrange
      final TelemetryAttributes attributes = <String, Object?>{
        'na${String.fromCharCode(0)}me': 1,
      };

      // Act
      final result = checkTelemetryAttributes(
        attributes,
        port: PortName.logging,
        operation: 'emit',
      );

      // Assert
      final Problem problem = expectErr(result);
      expect(problem.data['field'], 'attributes');
    });

    test('rejects a non-primitive value', () {
      // Arrange
      final TelemetryAttributes attributes = const <String, Object?>{
        'nested': <String, Object?>{},
      };

      // Act
      final result = checkTelemetryAttributes(
        attributes,
        port: PortName.metrics,
        operation: 'emit',
      );

      // Assert
      final Problem problem = expectErr(result);
      expect(problem.data['field'], 'attributes.nested');
    });

    test('rejects a non-finite number', () {
      // Arrange
      final TelemetryAttributes attributes = const <String, Object?>{
        'ratio': double.nan,
      };

      // Act
      final result = checkTelemetryAttributes(
        attributes,
        port: PortName.metrics,
        operation: 'emit',
      );

      // Assert
      final Problem problem = expectErr(result);
      expect(problem.data['field'], 'attributes.ratio');
    });

    test('rejects a null value', () {
      // Arrange
      const TelemetryAttributes attributes = <String, Object?>{'absent': null};

      // Act
      final result = _check(attributes);

      // Assert
      final Problem problem = expectErr(result);
      expect(problem.data['field'], 'attributes.absent');
    });
  });

  test('emptyTelemetryAttributes is unmodifiable', () {
    // Arrange
    final TelemetryAttributes attributes = emptyTelemetryAttributes;

    // Act
    void mutate() => attributes['x'] = 1;

    // Assert
    expect(mutate, throwsUnsupportedError);
  });
}
