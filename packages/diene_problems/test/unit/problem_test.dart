import 'package:diene_problems/diene_problems.dart';
import 'package:test/test.dart';

void main() {
  group('Problem', () {
    test('serializes every member and the data extension', () {
      // Arrange
      const Problem problem = Problem(
        type: 'https://h/docs/l/p/s/m/v1/entity_not_found',
        title: 'Entity not found',
        status: 404,
        detail: 'User 42 does not exist',
        instance: '/user/42',
        data: <String, Object?>{'entityType': 'user', 'id': '42'},
      );

      // Act
      final Map<String, Object?> json = problem.toJson();

      // Assert
      expect(json, <String, Object?>{
        'type': 'https://h/docs/l/p/s/m/v1/entity_not_found',
        'title': 'Entity not found',
        'status': 404,
        'detail': 'User 42 does not exist',
        'instance': '/user/42',
        'recoverable': false,
        'data': <String, Object?>{'entityType': 'user', 'id': '42'},
      });
      expect(Problem.fromJson(json), problem);
      expect(Problem.fromJson(json).hashCode, problem.hashCode);
      expect(problem.toString(), contains('404'));
    });

    test('omits data, detail and instance when absent', () {
      // Arrange
      const Problem problem = Problem(
        type: 't',
        title: 'T',
        status: 401,
        recoverable: true,
      );

      // Act
      final Map<String, Object?> json = problem.toJson();

      // Assert
      expect(json.containsKey('data'), isFalse);
      expect(json.containsKey('detail'), isFalse);
      expect(json.containsKey('instance'), isFalse);
      expect(json['recoverable'], isTrue);
    });

    test('reads a null or non-object data member as no data', () {
      // Arrange
      final List<Map<String, Object?>> wires = <Map<String, Object?>>[
        <String, Object?>{'type': 't', 'title': 'T', 'status': 400},
        <String, Object?>{
          'type': 't',
          'title': 'T',
          'status': 400,
          'data': null,
        },
        <String, Object?>{'type': 't', 'title': 'T', 'status': 400, 'data': 1},
      ];

      // Act
      final List<Problem> problems = wires.map(Problem.fromJson).toList();

      // Assert
      for (final Problem problem in problems) {
        expect(problem.data, isNull);
      }
    });

    test('defaults missing members and stringifies data keys', () {
      // Arrange
      final Map<String, Object?> wire = <String, Object?>{
        'status': 503.0,
        'data': <Object?, Object?>{1: 'one'},
      };

      // Act
      final Problem problem = Problem.fromJson(wire);

      // Assert
      expect(problem.type, 'about:blank');
      expect(problem.title, 'Unexpected problem');
      expect(problem.status, 503);
      expect(problem.recoverable, isFalse);
      expect(problem.data, <String, Object?>{'1': 'one'});
      expect(Problem.fromJson(const <String, Object?>{}).status, 500);
    });

    test('compares by wire form', () {
      // Arrange
      const Problem a = Problem(type: 't', title: 'T', status: 400);
      const Problem b = Problem(type: 't', title: 'T', status: 409);

      // Act
      final bool same = a == a;
      final bool different = a == b;

      // Assert
      expect(same, isTrue);
      expect(different, isFalse);
      expect(a == Object(), isFalse);
    });
  });
}
