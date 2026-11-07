import 'package:diene_core_utils/diene_core_utils.dart';
import 'package:diene_problems/diene_problems.dart';
import 'package:diene_result/diene_result.dart';
import 'package:test/test.dart';

void main() {
  group('slugify', () {
    test('lowercases and collapses runs of non-alphanumerics', () {
      // Arrange
      final List<String> inputs = <String>[
        'Hello World',
        'Hello   ---   World',
        'a1B2',
      ];

      // Act
      final List<String> slugs = inputs.map(slugify).toList();

      // Assert
      expect(slugs, <String>['hello-world', 'hello-world', 'a1b2']);
    });

    test('strips leading and trailing hyphens', () {
      // Arrange
      final List<String> inputs = <String>['  --Hello--  ', '!!!edge!!!'];

      // Act
      final List<String> slugs = inputs.map(slugify).toList();

      // Assert
      expect(slugs, <String>['hello', 'edge']);
    });

    test('folds accents away via NFKD rather than dropping the letter', () {
      // Arrange
      final List<String> inputs = <String>[
        'Crème Brûlée',
        'Ångström',
        'naïve café',
      ];

      // Act
      final List<String> slugs = inputs.map(slugify).toList();

      // Assert
      expect(slugs, <String>['creme-brulee', 'angstrom', 'naive-cafe']);
    });

    test(
      'a string with nothing retainable slugifies to empty, not an error',
      () {
        // Arrange
        final List<String> inputs = <String>['', '---', '!!!', '   '];

        // Act
        final List<String> slugs = inputs.map(slugify).toList();

        // Assert
        expect(slugs, <String>['', '', '', '']);
      },
    );

    test('is idempotent on its own output', () {
      // Arrange
      final List<String> inputs = <String>[
        'Hello World',
        'Crème Brûlée',
        'a--b',
        '',
      ];

      // Act
      final List<String> once = inputs.map(slugify).toList();
      final List<String> twice = once.map(slugify).toList();

      // Assert
      for (int i = 0; i < inputs.length; i++) {
        expect(twice[i], once[i], reason: 'not idempotent for "${inputs[i]}"');
      }
    });
  });

  group('namespacedKey', () {
    test('composes slugified parts with a colon', () {
      // Arrange
      const List<List<String>> parts = <List<String>>[
        <String>['Diene', 'Core Utils'],
        <String>['  ACME  ', 'App__Name'],
      ];

      // Act
      final List<String> keys = parts
          .map((List<String> pair) => namespacedKey(pair[0], pair[1]).unwrap())
          .toList();

      // Assert
      expect(keys, <String>['diene:core-utils', 'acme:app-name']);
    });

    test('accepts raw human text on both sides', () {
      // Arrange
      const String namespace = 'Crème Brûlée';
      const String key = 'Naïve Café';

      // Act
      final Result<String> composed = namespacedKey(namespace, key);

      // Assert
      expect(composed.unwrap(), 'creme-brulee:naive-cafe');
    });

    test('an empty-slugifying namespace fails as a value', () {
      // Arrange
      const String namespace = '---';

      // Act
      final Result<String> result = namespacedKey(namespace, 'key');

      // Assert
      expect(result.isErr, isTrue);
      final Problem problem = result.unwrapErr();
      expect(problem.status, 400);
      expect(problem.recoverable, isFalse);
      expect(problem.data['util'], 'slug');
      expect(problem.data['code'], 'invalid_input');
      expect(problem.data['field'], 'namespace');
      expect(problem.data['operation'], 'namespacedKey');
      expect(problem.type, endsWith('slug_invalid_input'));
      expect(
        problem.detail,
        'slug.namespacedKey: namespace must not slugify to empty',
      );
    });

    test('an empty-slugifying key fails as a value naming the key field', () {
      // Arrange
      const String key = '!!!';

      // Act
      final Result<String> result = namespacedKey('diene', key);

      // Assert
      expect(result.isErr, isTrue);
      expect(result.unwrapErr().data['field'], 'key');
    });

    test('a failure short-circuits the published Result combinators', () {
      // Arrange
      int mapped = 0;

      // Act
      final Result<int> chained = namespacedKey('', 'key')
          .andThen((String key) => Ok<int>(key.length))
          .map((int length) {
            mapped += 1;
            return length * 2;
          });

      // Assert
      expect(chained.isErr, isTrue);
      expect(mapped, 0, reason: 'map ran on an Err');
      expect(chained.unwrapOr(-1), -1);
    });

    test('a success flows through the published Result combinators', () {
      // Arrange
      const String namespace = 'diene';
      const String key = 'core-utils';

      // Act
      final Result<int> ok = namespacedKey(namespace, key)
          .andThen((String composed) => Ok<int>(composed.length))
          .map((int length) => length * 2);

      // Assert
      expect(ok.unwrap(), 'diene:core-utils'.length * 2);
      expect(ok.ok().isSome, isTrue);
      expect(ok.err().isNone, isTrue);
    });
  });

  group('NamespacedKeyField', () {
    test('names both components exactly once', () {
      // Arrange
      final List<NamespacedKeyField> fields = NamespacedKeyField.values;

      // Act
      final List<String> names = fields
          .map((NamespacedKeyField f) => f.name)
          .toList();

      // Assert
      expect(names, <String>['namespace', 'key']);
    });
  });
}
