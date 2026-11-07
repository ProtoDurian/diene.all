import 'package:diene_core_utils/diene_core_utils.dart';
import 'package:test/test.dart';

void main() {
  group('deepClone', () {
    test('rebuilds maps and lists so no mutable structure is shared', () {
      // Arrange
      final JsonObject source = <String, Object?>{
        'a': <String, Object?>{
          'b': <Object?>[1, 2],
        },
      };

      // Act
      final JsonObject clone = deepClone(source)! as JsonObject;
      final JsonObject clonedInner = clone['a']! as JsonObject;
      (clonedInner['b']! as List<Object?>).add(3);

      // Assert
      expect(identical(clone, source), isFalse);
      expect(
        ((source['a']! as JsonObject)['b']! as List<Object?>),
        <Object?>[1, 2],
        reason: 'mutating the clone reached the source',
      );
    });

    test('an untouched clone equals its source', () {
      // Arrange
      final JsonObject source = <String, Object?>{
        'a': <String, Object?>{
          'b': <Object?>[1, 2],
        },
      };

      // Act
      final JsonObject clone = deepClone(source)! as JsonObject;

      // Assert
      expect(clone, source);
    });

    test('passes scalars and null through unchanged', () {
      // Arrange
      final List<Object?> inputs = <Object?>[null, 1, 'x', true, 1.5];

      // Act
      final List<Object?> cloned = inputs.map(deepClone).toList();

      // Assert
      expect(cloned, inputs);
    });
  });

  group('canonicalConfigKey / configKeysMatch', () {
    test('every separator and case spelling canonicalises alike', () {
      // Arrange
      final List<String> spellings = <String>[
        'display-name',
        'display_name',
        'displayName',
        'DisplayName',
        'DISPLAY_NAME',
        'Display-Name',
      ];

      // Act
      final List<String> canonical = spellings.map(canonicalConfigKey).toList();
      final List<bool> matches = spellings
          .map((String spelling) => configKeysMatch(spelling, 'displayName'))
          .toList();

      // Assert
      for (int i = 0; i < spellings.length; i++) {
        expect(
          canonical[i],
          'displayname',
          reason: '${spellings[i]} canonicalised wrong',
        );
        expect(matches[i], isTrue, reason: spellings[i]);
      }
    });

    test('genuinely different keys do not match', () {
      // Arrange
      const String left = 'displayName';
      const String right = 'display_names';

      // Act
      final bool matches = configKeysMatch(left, right);
      final String blank = canonicalConfigKey('');

      // Assert
      expect(matches, isFalse);
      expect(blank, '');
    });
  });

  group('deepMerge', () {
    test('merges nested maps recursively', () {
      // Arrange
      final JsonObject base = <String, Object?>{
        'app': <String, Object?>{'name': 'base', 'retries': 1},
      };
      final JsonObject overlay = <String, Object?>{
        'app': <String, Object?>{'retries': 2},
      };

      // Act
      final JsonObject merged = deepMerge(base, overlay);

      // Assert
      expect(merged['app'], <String, Object?>{'name': 'base', 'retries': 2});
    });

    test('lists and scalars replace wholesale — there is no append', () {
      // Arrange
      final JsonObject base = <String, Object?>{
        'tags': <Object?>['a', 'b'],
        'n': 1,
      };
      final JsonObject overlay = <String, Object?>{
        'tags': <Object?>['c'],
        'n': 2,
      };

      // Act
      final JsonObject merged = deepMerge(base, overlay);

      // Assert
      expect(merged['tags'], <Object?>['c']);
      expect(merged['n'], 2);
    });

    test('a map overlaying a scalar replaces it', () {
      // Arrange
      final JsonObject base = <String, Object?>{'k': 1};
      final JsonObject overlay = <String, Object?>{
        'k': <String, Object?>{'nested': true},
      };

      // Act
      final JsonObject merged = deepMerge(base, overlay);

      // Assert
      expect(merged['k'], <String, Object?>{'nested': true});
    });

    test('a scalar overlaying a map replaces it', () {
      // Arrange
      final JsonObject base = <String, Object?>{
        'k': <String, Object?>{'nested': true},
      };
      final JsonObject overlay = <String, Object?>{'k': 1};

      // Act
      final JsonObject merged = deepMerge(base, overlay);

      // Assert
      expect(merged['k'], 1);
    });

    test(
      "the base layer's key spelling survives a differently-spelled overlay",
      () {
        // Arrange
        final JsonObject base = <String, Object?>{'display-name': 'base'};
        final JsonObject overlay = <String, Object?>{'DisplayName': 'overlay'};

        // Act
        final JsonObject merged = deepMerge(base, overlay);

        // Assert
        expect(merged.keys, <String>['display-name']);
        expect(merged['display-name'], 'overlay');
      },
    );

    test('an overlay key absent from the base keeps the overlay spelling', () {
      // Arrange
      final JsonObject base = <String, Object?>{'a': 1};
      final JsonObject overlay = <String, Object?>{'newKey': 2};

      // Act
      final JsonObject merged = deepMerge(base, overlay);

      // Assert
      expect(merged.keys, <String>['a', 'newKey']);
    });

    test(
      'two differently-spelled overlay keys collapse onto one output key',
      () {
        // Arrange
        final JsonObject base = <String, Object?>{};
        final JsonObject overlay = <String, Object?>{
          'display_name': 'first',
          'displayName': 'second',
        };

        // Act
        final JsonObject merged = deepMerge(base, overlay);

        // Assert
        expect(merged.keys, <String>['display_name']);
        expect(merged['display_name'], 'second');
      },
    );

    test('neither input is mutated', () {
      // Arrange
      final JsonObject base = <String, Object?>{
        'app': <String, Object?>{'name': 'base'},
      };
      final JsonObject overlay = <String, Object?>{
        'app': <String, Object?>{'name': 'overlay'},
      };

      // Act
      deepMerge(base, overlay);

      // Assert
      expect((base['app']! as JsonObject)['name'], 'base');
      expect((overlay['app']! as JsonObject)['name'], 'overlay');
    });

    test('the merged result shares no structure with either input', () {
      // Arrange
      final JsonObject overlay = <String, Object?>{
        'tags': <Object?>['a'],
      };

      // Act
      final JsonObject merged = deepMerge(<String, Object?>{}, overlay);
      (merged['tags']! as List<Object?>).add('b');

      // Assert
      expect(overlay['tags'], <Object?>['a']);
    });
  });

  group('deepMergeAll', () {
    test('folds layers from lowest to highest precedence', () {
      // Arrange
      final List<JsonObject> layers = <JsonObject>[
        <String, Object?>{'a': 1, 'b': 1, 'c': 1},
        <String, Object?>{'b': 2, 'c': 2},
        <String, Object?>{'c': 3},
      ];

      // Act
      final JsonObject merged = deepMergeAll(layers);

      // Assert
      expect(merged, <String, Object?>{'a': 1, 'b': 2, 'c': 3});
    });

    test('no layers yields an empty object', () {
      // Arrange
      final List<JsonObject> layers = <JsonObject>[];

      // Act
      final JsonObject merged = deepMergeAll(layers);

      // Assert
      expect(merged, isEmpty);
    });

    test('one layer is cloned, not aliased', () {
      // Arrange
      final JsonObject only = <String, Object?>{'a': 1};

      // Act
      final JsonObject merged = deepMergeAll(<JsonObject>[only]);

      // Assert
      expect(merged, only);
      expect(identical(merged, only), isFalse);
    });
  });
}
