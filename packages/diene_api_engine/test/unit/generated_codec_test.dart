library;

import 'package:diene_api_engine/src/generated/export.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('UserProfile codec', () {
    test('decodes a full user profile and round-trips byte-equal', () {
      // Arrange
      const Map<String, Object?> wire = <String, Object?>{
        'id': 'usr_42',
        'email': 'a@example.test',
        'displayName': 'Ada',
      };

      // Act
      final UserProfile decoded = UserProfile.fromJson(wire);

      // Assert
      expect(decoded.id, 'usr_42');
      expect(decoded.email, 'a@example.test');
      expect(decoded.displayName, 'Ada');
      expect(decoded.toJson(), wire);
    });

    test('the optional displayName decodes as null and survives encoding', () {
      // Arrange
      const Map<String, Object?> wire = <String, Object?>{
        'id': 'usr_43',
        'email': 'b@example.test',
      };

      // Act
      final UserProfile decoded = UserProfile.fromJson(wire);

      // Assert
      expect(decoded.displayName, isNull);
      expect(decoded.toJson(), <String, Object?>{
        'id': 'usr_43',
        'email': 'b@example.test',
        'displayName': null,
      });
    });
  });

  group('ProblemDetails codec', () {
    test('decodes full problem details and round-trips byte-equal', () {
      // Arrange
      const Map<String, Object?> wire = <String, Object?>{
        'type': 'https://docs.example.test/docs/l/p/s/m/v1/entity_not_found',
        'title': 'Entity not found',
        'status': 404,
        'detail': 'User 42 does not exist',
        'instance': '/user/42',
      };

      // Act
      final ProblemDetails decoded = ProblemDetails.fromJson(wire);

      // Assert
      expect(decoded.type, wire['type']);
      expect(decoded.title, 'Entity not found');
      expect(decoded.status, 404);
      expect(decoded.detail, 'User 42 does not exist');
      expect(decoded.instance, '/user/42');
      expect(decoded.toJson(), wire);
    });

    test('both optional fields decode as null', () {
      // Arrange
      const Map<String, Object?> wire = <String, Object?>{
        'type': 'urn:example:problem',
        'title': 'Bad request',
        'status': 400,
      };

      // Act
      final ProblemDetails decoded = ProblemDetails.fromJson(wire);

      // Assert
      expect(decoded.detail, isNull);
      expect(decoded.instance, isNull);
    });

    test('a numeric status arriving as a double is coerced to int', () {
      // Arrange
      // Act
      final ProblemDetails decoded = ProblemDetails.fromJson(<String, Object?>{
        'type': 'urn:example:problem',
        'title': 'Server error',
        'status': 500.0,
      });

      // Assert
      expect(decoded.status, 500);
      expect(decoded.status, isA<int>());
    });

    test('the const constructor builds an equivalent object', () {
      // Arrange
      // Act
      const ProblemDetails built = ProblemDetails(
        type: 'urn:example:problem',
        title: 'Conflict',
        status: 409,
      );

      // Assert
      expect(built.toJson(), <String, Object?>{
        'type': 'urn:example:problem',
        'title': 'Conflict',
        'status': 409,
        'detail': null,
        'instance': null,
      });
    });
  });
}
