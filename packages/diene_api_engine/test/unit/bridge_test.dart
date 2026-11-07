import 'package:diene_api_engine/diene_api_engine.dart';
import 'package:diene_api_engine/test_helper.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, Object?> _decode(Map<String, Object?> json) => json;

void main() {
  group('toResult reconciliation matrix', () {
    test('network failure → transport-failure problem', () {
      // Arrange
      // Act
      final Result<Map<String, Object?>> result = toResult(
        networkFailure('refused'),
        decode: _decode,
      );

      // Assert
      final Problem p = expectErr(result);
      expect(p.type, BridgeProblems.transportFailure);
      expect(p.status, 503);
      expect(p.data['reason'], 'refused');
    });

    test('2xx JSON → Ok(decoded)', () {
      // Arrange
      // Act
      final Result<Map<String, Object?>> result = toResult(
        okJson(<String, Object?>{'a': 1}),
        decode: _decode,
      );

      // Assert
      expect(expectOk(result)['a'], 1);
    });

    test('2xx non-JSON body → transport-failure', () {
      // Arrange
      // Act
      final Result<Map<String, Object?>> result = toResult(
        const Received(HttpResponse(status: 200, body: 'plain text')),
        decode: _decode,
      );

      // Assert
      expectProblemType(result, BridgeProblems.transportFailure);
    });

    test('2xx that fails to decode → transport-failure', () {
      // Arrange
      // Act
      final Result<int> result = toResult<int>(
        okJson(<String, Object?>{'a': 1}),
        decode: (Map<String, Object?> _) => throw StateError('bad'),
      );

      // Assert
      expectProblemType(result, BridgeProblems.transportFailure);
    });

    test('error problem body → that Problem (incl. nested data)', () {
      // Arrange
      final Problem source = problemFixture(
        type: 'urn:diene:problem:conflict',
        status: 409,
        data: const <String, Object?>{
          'nested': <String, Object?>{'type': 'inner', 'status': 400},
        },
      );

      // Act
      final Result<Map<String, Object?>> result = toResult(
        problemResponse(source),
        decode: _decode,
      );

      // Assert
      final Problem p = expectProblemType(result, source.type);
      expect(p.status, 409);
      expect(p.data['nested'], isA<Map<Object?, Object?>>());
    });

    test('error JSON that is not a problem → unexpected-response', () {
      // Arrange
      // Act
      final Result<Map<String, Object?>> result = toResult(
        nonProblemJson(<String, Object?>{'message': 'nope'}, status: 400),
        decode: _decode,
      );

      // Assert
      final Problem p = expectProblemType(
        result,
        BridgeProblems.unexpectedResponse,
      );
      expect(p.status, 400);
    });

    test('non-JSON error body → transport-failure with snippet', () {
      // Arrange
      // Act
      final Result<Map<String, Object?>> result = toResult(
        nonJsonResponse(status: 502),
        decode: _decode,
      );

      // Assert
      final Problem p = expectProblemType(
        result,
        BridgeProblems.transportFailure,
      );
      expect(p.status, 502);
      expect(p.data['bodySnippet'], 'Bad Gateway');
    });
  });

  group('guards', () {
    test('isProblemJson requires type + status', () {
      // Arrange
      // Act
      // Assert
      expect(
        isProblemJson(<String, Object?>{'type': 't', 'status': 400}),
        isTrue,
      );
      expect(isProblemJson(<String, Object?>{'type': 't'}), isFalse);
      expect(isProblemJson('nope'), isFalse);
    });
  });
}
