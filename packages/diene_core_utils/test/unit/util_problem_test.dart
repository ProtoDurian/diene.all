import 'package:diene_core_utils/diene_core_utils.dart';
import 'package:diene_problems/diene_problems.dart';
import 'package:diene_result/diene_result.dart';
import 'package:test/test.dart';

void main() {
  group('wire-id law', () {
    test('every UtilName wire id matches the cross-language pattern', () {
      // Arrange
      final RegExp pattern = RegExp(r'^[a-z][a-z0-9_]*$');

      // Act
      final Map<UtilName, bool> legal = <UtilName, bool>{
        for (final UtilName util in UtilName.values)
          util: pattern.hasMatch(util.wireId),
      };

      // Assert
      legal.forEach((UtilName util, bool isLegal) {
        expect(
          isLegal,
          isTrue,
          reason: '${util.name} wire id "${util.wireId}" is not snake_case',
        );
        expect(util.wireId, util.name);
      });
    });

    test('every UtilErrorCode wire id matches the pattern', () {
      // Arrange
      final RegExp pattern = RegExp(r'^[a-z][a-z0-9_]*$');

      // Act
      final Map<UtilErrorCode, bool> legal = <UtilErrorCode, bool>{
        for (final UtilErrorCode code in UtilErrorCode.values)
          code: pattern.hasMatch(code.wireId),
      };

      // Assert
      legal.forEach((UtilErrorCode code, bool isLegal) {
        expect(
          isLegal,
          isTrue,
          reason: '${code.name} wire id "${code.wireId}" is not snake_case',
        );
      });
    });

    test('the COMPOSED id is legal, not merely each half', () {
      // Arrange
      final RegExp pattern = RegExp(r'^[a-z][a-z0-9_]*$');

      // Act
      final List<String> composed = <String>[
        for (final UtilName util in UtilName.values)
          for (final UtilErrorCode code in UtilErrorCode.values)
            '${util.wireId}_${code.wireId}',
      ];

      // Assert
      for (final String id in composed) {
        expect(
          pattern.hasMatch(id),
          isTrue,
          reason: 'composed id "$id" is not a legal wire id',
        );
      }
    });

    test('wire ids are unique within each vocabulary', () {
      // Arrange
      final List<UtilName> utils = UtilName.values;
      final List<UtilErrorCode> codes = UtilErrorCode.values;

      // Act
      final Set<String> utilIds = utils.map((UtilName u) => u.wireId).toSet();
      final Set<String> codeIds = codes
          .map((UtilErrorCode c) => c.wireId)
          .toSet();

      // Assert
      expect(utilIds, hasLength(utils.length));
      expect(codeIds, hasLength(codes.length));
    });
  });

  group('status and recoverability', () {
    test('each code carries a plausible HTTP status', () {
      // Arrange
      final Map<UtilErrorCode, int> expected = <UtilErrorCode, int>{
        UtilErrorCode.invalidInput: 400,
        UtilErrorCode.invalidFormat: 400,
        UtilErrorCode.conflict: 409,
        UtilErrorCode.unprojectable: 422,
        UtilErrorCode.delegated: 500,
      };

      // Act
      final Map<UtilErrorCode, int> actual = <UtilErrorCode, int>{
        for (final UtilErrorCode code in expected.keys) code: code.status,
      };

      // Assert
      expect(actual, expected);
    });

    test(
      'no code claims recoverability, because none of them is retryable',
      () {
        // Arrange
        final List<UtilErrorCode> codes = UtilErrorCode.values;

        // Act
        final Map<UtilErrorCode, bool> recoverable = <UtilErrorCode, bool>{
          for (final UtilErrorCode code in codes) code: code.recoverable,
        };

        // Assert
        recoverable.forEach((UtilErrorCode code, bool value) {
          expect(
            value,
            isFalse,
            reason: '${code.name} claims a retry this library cannot honour',
          );
        });
      },
    );
  });

  group('utilProblem', () {
    test('mints the envelope through the single builder', () {
      // Arrange
      const String message = 'namespace must not slugify to empty';

      // Act
      final Problem problem = utilProblem(
        util: UtilName.slug,
        code: UtilErrorCode.invalidInput,
        operation: 'namespacedKey',
        message: message,
      );

      // Assert
      expect(problem.title, message);
      expect(problem.status, 400);
      expect(problem.recoverable, isFalse);
      expect(
        problem.detail,
        'slug.namespacedKey: namespace must not slugify to empty',
      );
      expect(problem.data['util'], 'slug');
      expect(problem.data['code'], 'invalid_input');
      expect(problem.data['operation'], 'namespacedKey');
      expect(
        problem.type,
        problemTypeUri(
          portal: ErrorPortal.localError,
          version: coreUtilsProblemVersion,
          id: 'slug_invalid_input',
        ),
      );
    });

    test('extra details merge into data without displacing the fixed keys', () {
      // Arrange
      final Map<String, Object?> details = <String, Object?>{
        'field': 'ACME_A',
        'path': 'a',
      };

      // Act
      final Problem problem = utilProblem(
        util: UtilName.coercion,
        code: UtilErrorCode.conflict,
        operation: 'environmentToNestedMap',
        message: 'clash',
        details: details,
      );

      // Assert
      expect(problem.data['util'], 'coercion');
      expect(problem.data['code'], 'conflict');
      expect(problem.data['operation'], 'environmentToNestedMap');
      expect(problem.data['field'], 'ACME_A');
      expect(problem.data['path'], 'a');
    });

    test('a real portal moves the URI host without changing the id', () {
      // Arrange
      final Problem local = utilProblem(
        util: UtilName.wire,
        code: UtilErrorCode.invalidFormat,
        operation: 'parse',
        message: 'nope',
      );

      // Act
      final Problem hosted = utilProblem(
        util: UtilName.wire,
        code: UtilErrorCode.invalidFormat,
        operation: 'parse',
        message: 'nope',
        portal: ErrorPortal.localError,
      );

      // Assert
      expect(hosted.type, local.type);
      expect(local.type, endsWith('wire_invalid_format'));
    });

    test('the version segment is part of the contract identity', () {
      // Arrange
      final String version = coreUtilsProblemVersion;

      // Act
      final Problem problem = utilProblem(
        util: UtilName.record,
        code: UtilErrorCode.unprojectable,
        operation: 'stableConfig',
        message: 'cycle',
      );

      // Assert
      expect(version, 'v1');
      expect(problem.type, contains('/v1/'));
    });
  });

  group('failure sugar', () {
    test('utilFailure produces an Err carrying utilProblem output', () {
      // Arrange
      final Problem expected = utilProblem(
        util: UtilName.timing,
        code: UtilErrorCode.invalidInput,
        operation: 'sleep',
        message: 'negative',
      );

      // Act
      final Err<int> failure = utilFailure<int>(
        util: UtilName.timing,
        code: UtilErrorCode.invalidInput,
        operation: 'sleep',
        message: 'negative',
      );

      // Assert
      expect(failure.isErr, isTrue);
      expect(failure.problem.type, expected.type);
    });

    test('utilFailure forwards details and portal', () {
      // Arrange
      final Map<String, Object?> details = <String, Object?>{
        'paths': <String>['/a'],
      };

      // Act
      final Err<int> failure = utilFailure<int>(
        util: UtilName.vfs,
        code: UtilErrorCode.delegated,
        operation: 'load',
        message: 'downstream',
        portal: ErrorPortal.localError,
        details: details,
      );

      // Assert
      expect(failure.problem.data['paths'], <String>['/a']);
    });

    test('invalidUtilInput names the offending field', () {
      // Arrange
      const String field = 'namespace';

      // Act
      final Err<String> failure = invalidUtilInput<String>(
        util: UtilName.slug,
        operation: 'namespacedKey',
        field: field,
        message: 'empty',
      );

      // Assert
      expect(failure.problem.data['field'], 'namespace');
      expect(failure.problem.data['code'], 'invalid_input');
      expect(failure.problem.status, 400);
    });

    test('invalidWireFormat names the grammar and the rejected value', () {
      // Arrange
      const String value = '21-07-2026';

      // Act
      final Err<int> failure = invalidWireFormat<int>(
        operation: 'WireDate.parse',
        expected: wireDateGrammar,
        value: value,
      );

      // Assert
      expect(failure.problem.data['util'], 'wire');
      expect(failure.problem.data['expected'], wireDateGrammar);
      expect(failure.problem.data['value'], '21-07-2026');
      expect(failure.problem.title, 'expected $wireDateGrammar');
    });
  });

  group('the envelope survives the published Result wire codec', () {
    test('an Err round-trips through the tagged-array form', () {
      // Arrange
      final Result<String> failure = namespacedKey('---', 'key');

      // Act
      final ResultSerial encoded = failure.serial();
      final Result<String> decoded = Result<String>.fromSerial(
        encoded,
        decodeOk: (Object? value) => value! as String,
      );

      // Assert
      expect(decoded.isErr, isTrue);
      expect(decoded.unwrapErr().type, failure.unwrapErr().type);
      expect(decoded.unwrapErr().data['field'], 'namespace');
    });
  });
}
