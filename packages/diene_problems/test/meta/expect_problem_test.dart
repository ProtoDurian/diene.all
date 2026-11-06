import 'package:diene_problems/diene_problems.dart';
import 'package:diene_problems/test_helper.dart';
import 'package:test/test.dart';

const Problem _good = Problem(
  type: 'https://h/docs/l/p/s/m/v1/conflict',
  title: 'Conflict',
  status: 409,
  detail: 'Note 7 changed',
  instance: '/notes/7',
  recoverable: true,
  data: <String, Object?>{
    'entityType': 'note',
    'id': '7',
    'tags': <Object?>[
      'a',
      <String, Object?>{'b': 1},
    ],
  },
);

Matcher _mismatch(String text) => throwsA(
  isA<ProblemMatcherError>()
      .having(
        (ProblemMatcherError e) => e,
        'is an AssertionError',
        isA<AssertionError>(),
      )
      .having((ProblemMatcherError e) => e.message, 'message', contains(text)),
);

void main() {
  group('expectProblem', () {
    test('passes on a known-good Problem with every field given', () {
      // Arrange
      final Map<String, Object?> data = <String, Object?>{
        'entityType': 'note',
        'id': '7',
        'tags': <Object?>[
          'a',
          <String, Object?>{'b': 1},
        ],
      };

      // Act
      void act() => expectProblem(
        _good,
        type: 'https://h/docs/l/p/s/m/v1/conflict',
        title: 'Conflict',
        status: 409,
        recoverable: true,
        detail: 'Note 7 changed',
        instance: '/notes/7',
        data: data,
      );

      // Assert
      expect(act, returnsNormally);
      expect(() => expectProblem(_good), returnsNormally);
    });

    test('fails on a value that is not a Problem', () {
      // Arrange
      const Object notAProblem = 'boom';

      // Act
      void act() => expectProblem(notAProblem);

      // Assert
      expect(act, _mismatch('expected a Problem but got String'));
      expect(() => expectProblem(null), _mismatch('got Null'));
    });

    test('names the first mismatched envelope field', () {
      // Arrange
      final Map<String, void Function()> bad = <String, void Function()>{
        'Problem.type mismatch': () => expectProblem(_good, type: 'x'),
        'Problem.title mismatch': () => expectProblem(_good, title: 'x'),
        'Problem.status mismatch': () => expectProblem(_good, status: 500),
        'Problem.recoverable mismatch': () =>
            expectProblem(_good, recoverable: false),
        'Problem.detail mismatch': () => expectProblem(_good, detail: 'x'),
        'Problem.instance mismatch': () => expectProblem(_good, instance: 'x'),
      };

      // Act
      void act(String text, void Function() call) =>
          expect(call, _mismatch(text));

      // Assert
      bad.forEach(act);
    });

    test('compares data deeply and fails on any difference', () {
      // Arrange
      final List<Map<String, Object?>> wrong = <Map<String, Object?>>[
        <String, Object?>{'entityType': 'note'},
        <String, Object?>{
          'entityType': 'note',
          'id': '7',
          'other': <Object?>[],
        },
        <String, Object?>{'entityType': 'note', 'id': '8', 'tags': <Object?>[]},
        <String, Object?>{
          'entityType': 'note',
          'id': '7',
          'tags': <Object?>['a'],
        },
        <String, Object?>{
          'entityType': 'note',
          'id': '7',
          'tags': <Object?>[
            'a',
            <String, Object?>{'b': 2},
          ],
        },
      ];

      // Act
      void act(Map<String, Object?> data) => expect(
        () => expectProblem(_good, data: data),
        _mismatch('Problem.data'),
      );

      // Assert
      wrong.forEach(act);
    });

    test('noData passes on a data-less Problem and fails otherwise', () {
      // Arrange
      const Problem dataLess = Problem(type: 't', title: 'T', status: 401);

      // Act
      void act() => expectProblem(dataLess, noData: true);

      // Assert
      expect(act, returnsNormally);
      expect(
        () => expectProblem(_good, noData: true),
        _mismatch('Problem.data mismatch: expected <null>'),
      );
    });
  });
}
