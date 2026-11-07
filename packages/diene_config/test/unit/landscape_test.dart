import 'package:diene_config/diene_config.dart';
import 'package:diene_config/test_helper.dart';
import 'package:diene_problems/diene_problems.dart';
import 'package:diene_result/diene_result.dart';
import 'package:test/test.dart';

import '../support.dart';

void main() {
  group('landscape', () {
    test('returns the injected store track', () {
      // Arrange
      const LandscapeSource source = FakeLandscapeSource('lapras');

      // Act
      final Result<String> track = landscape(source: source);

      // Assert
      expect(track, isOk, reason: describe(track));
      expect(track.unwrap(), 'lapras');
    });

    test('returns an explicitly injected define value', () {
      // Arrange
      const LandscapeSource source = DartDefineLandscapeSource(value: 'pichu');

      // Act
      final Result<String> track = landscape(source: source);

      // Assert
      expect(track, isOk, reason: describe(track));
      expect(track.unwrap(), 'pichu');
    });

    test('trims surrounding whitespace', () {
      // Arrange
      const LandscapeSource source = FakeLandscapeSource('  pichu \n');

      // Act
      final Result<String> track = landscape(source: source);

      // Assert
      expect(track, isOk, reason: describe(track));
      expect(track.unwrap(), 'pichu');
    });

    test('reports an empty value as landscape_missing', () {
      // Arrange
      const LandscapeSource source = FakeLandscapeSource('');

      // Act
      final Result<String> track = landscape(source: source);

      // Assert
      expect(track, isErr, reason: describe(track));
      final Problem problem = track.unwrapErr();
      expect(problem.data['code'], ConfigProblemCode.landscapeMissing.wireId);
      expect(problem.status, 400);
      expect(problem.data['define'], landscapeDefineKey);
      expect(problem.title, contains(landscapeDefineKey));
    });

    test(
      'treats a whitespace-only value as missing, not as an empty track',
      () {
        // Arrange
        const LandscapeSource source = FakeLandscapeSource('   ');

        // Act
        final Result<String> track = landscape(source: source);

        // Assert
        expect(track, isErr, reason: describe(track));
        expect(
          track.unwrapErr().data['code'],
          ConfigProblemCode.landscapeMissing.wireId,
        );
      },
    );

    test('treats a blank injected define as missing', () {
      // Arrange
      const LandscapeSource source = DartDefineLandscapeSource(value: ' \t ');

      // Act
      final Result<String> track = landscape(source: source);

      // Assert
      expect(track, isErr, reason: describe(track));
      expect(
        track.unwrapErr().data['code'],
        ConfigProblemCode.landscapeMissing.wireId,
      );
    });
  });

  group('DartDefineLandscapeSource', () {
    test('reads an explicitly supplied value', () {
      // Arrange
      const LandscapeSource source = DartDefineLandscapeSource(value: 'raichu');

      // Act
      final String value = source.read();

      // Assert
      expect(value, 'raichu');
    });

    test('defaults to the build define, which is empty in a test run', () {
      // Arrange
      const LandscapeSource source = DartDefineLandscapeSource();

      // Act
      final Result<String> track = landscape(source: source);

      // Assert
      expect(source.read(), '');
      expect(track, isErr, reason: describe(track));
    });

    test('is the default source, so landscape() alone reports missing', () {
      // Arrange
      final String expectedCode = ConfigProblemCode.landscapeMissing.wireId;

      // Act
      final Result<String> track = landscape();

      // Assert
      expect(track, isErr, reason: describe(track));
      expect(track.unwrapErr().data['code'], expectedCode);
    });

    test('depends only on the value it was given, with no detection', () {
      // Arrange
      const LandscapeSource injected = FakeLandscapeSource('lapras');
      const LandscapeSource define = DartDefineLandscapeSource(value: 'lapras');

      // Act
      final Result<String> fromFake = landscape(source: injected);
      final Result<String> fromDefine = landscape(source: define);

      // Assert
      expect(fromFake.unwrap(), 'lapras');
      expect(fromDefine.unwrap(), 'lapras');
    });
  });

  group('landscapeDefineKey', () {
    test('is the DIENE_LANDSCAPE define', () {
      // Arrange
      const String expected = 'DIENE_LANDSCAPE';

      // Act
      const String actual = landscapeDefineKey;

      // Assert
      expect(actual, expected);
    });
  });
}
