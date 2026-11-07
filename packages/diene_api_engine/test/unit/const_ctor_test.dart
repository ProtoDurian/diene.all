library;

import 'package:diene_api_engine/diene_api_engine.dart';
import 'package:diene_api_engine/test_helper.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ResultSdk built at runtime', () {
    test('a runtime instance behaves identically to a const one', () async {
      // Arrange
      final ResultSdk runtime = ResultSdk();
      const ResultSdk compileTime = ResultSdk();

      // Act
      // Assert
      expect((await runtime.call<int>(() async => 1)).unwrap(), 1);
      expect((await compileTime.call<int>(() async => 1)).unwrap(), 1);

      final Problem viaRuntime = expectErr(
        await runtime.call<int>(() async => throw StateError('boom')),
      );
      expect(viaRuntime.type, BridgeProblems.transportFailure);
      expect(viaRuntime.status, 503);
    });

    test('const instances are canonicalised, runtime ones are not', () {
      // Arrange
      // Act
      // Assert
      expect(identical(const ResultSdk(), const ResultSdk()), isTrue);
      expect(identical(ResultSdk(), ResultSdk()), isFalse);
    });
  });
}
