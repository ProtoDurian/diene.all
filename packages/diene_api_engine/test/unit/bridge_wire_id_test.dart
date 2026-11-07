import 'package:diene_api_engine/diene_api_engine.dart';
import 'package:diene_problems/diene_problems.dart'
    show problemWireIdPattern, r14WireId;
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('every BridgeProblems wire id is snake_case', () {
    final Map<String, String> ids = <String, String>{
      'transportFailure': BridgeProblems.transportFailure,
      'unexpectedResponse': BridgeProblems.unexpectedResponse,
      'duplicateBackend': BridgeProblems.duplicateBackend,
      'authTokenUnavailable': BridgeProblems.authTokenUnavailable,
    };

    test('the set under test is not empty', () {
      // Arrange
      // Act
      // Assert
      expect(ids, isNotEmpty);
      expect(ids.length, 4);
    });

    ids.forEach((String name, String uri) {
      test('$name yields an id matching the published pattern', () {
        // Arrange
        // Act
        final String wireId = uri.substring(uri.lastIndexOf('/') + 1);

        // Assert
        expect(
          wireId,
          isNotEmpty,
          reason: 'the type URI must end in a wire id',
        );
        expect(
          problemWireIdPattern.hasMatch(wireId),
          isTrue,
          reason:
              '$name produced wire id "$wireId", which violates the published '
              'problemWireIdPattern (snake_case, not kebab)',
        );
        expect(
          wireId.contains('-'),
          isFalse,
          reason: 'wire ids must use underscores instead of hyphens',
        );
      });
    });

    test('constructing each id does not throw', () {
      // Arrange
      // Act
      // Assert
      for (final String name in ids.keys) {
        expect(() => ids[name], returnsNormally, reason: name);
      }
    });
  });

  group('Wire id normalization is available and narrow', () {
    test('normalizes a kebab sample id into a legal wire id', () {
      // Arrange
      const String legacy = 'entity-not-found';

      // Act
      // Assert
      expect(problemWireIdPattern.hasMatch(legacy), isFalse);
      expect(problemWireIdPattern.hasMatch(r14WireId(legacy)), isTrue);
      expect(r14WireId(legacy), 'entity_not_found');
    });

    test('it is exactly hyphen to underscore, nothing else', () {
      // Arrange
      // Act
      // Assert
      expect(r14WireId('already_snake'), 'already_snake');
      expect(r14WireId('a-b-c'), 'a_b_c');
      expect(r14WireId('MiXeD-Case'), 'MiXeD_Case');
    });
  });
}
