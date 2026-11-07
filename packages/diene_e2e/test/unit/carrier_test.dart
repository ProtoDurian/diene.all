import 'package:diene_e2e/diene_e2e.dart';
import 'package:flutter_test/flutter_test.dart';

const String _nonce = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA';
const String _other = 'abcdefghijklmnopqrstuvwxyz0123456789-_ABCDE';
const String _carrier = 'atomi-app-handoff:v1:$_nonce';

bool _publishedRule(String nonce) =>
    nonce.length == 43 && RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(nonce);

const List<String> _samples = <String>[
  _nonce,
  _other,
  '',
  'AAAA',
  '${_nonce}A',
  'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=',
  'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA+',
  'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA/',
  'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA.',
  'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA\n',
  '\nAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
  'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAé',
];

void main() {
  group('nonce validation', () {
    test('accepts 43 base64url characters', () {
      // Arrange
      const List<String> nonces = <String>[_nonce, _other];

      // Act
      final List<bool> valid = nonces.map(isValidAppHandoffNonce).toList();

      // Assert
      expect(valid, <bool>[true, true]);
      expect(appHandoffNonceLength, 43);
    });

    test('rejects a wrong length, padding and other alphabets', () {
      // Arrange
      final List<String> bad = _samples.skip(2).toList();

      // Act
      final List<bool> valid = bad.map(isValidAppHandoffNonce).toList();

      // Assert
      expect(valid, everyElement(isFalse));
    });

    test('gives the same answer as the 1.0.0 rule for every sample', () {
      // Arrange
      final List<bool> expected = _samples.map(_publishedRule).toList();

      // Act
      final List<bool> actual = _samples.map(isValidAppHandoffNonce).toList();

      // Assert
      expect(actual, expected);
    });
  });

  group('canonical carrier', () {
    test('build then parse round-trips the nonce', () {
      // Arrange
      const String nonce = _other;

      // Act
      final String carrier = buildAppHandoffCarrier(nonce);

      // Assert
      expect(carrier, 'atomi-app-handoff:v1:$_other');
      expect(parseAppHandoffCarrier(carrier), nonce);
      expect(
        '$appHandoffCarrierScheme:$appHandoffCarrierVersion:',
        'atomi-app-handoff:v1:',
      );
    });

    test('build throws an ArgumentError on an invalid nonce', () {
      // Arrange
      const String nonce = 'AAAA';

      // Act
      void build() => buildAppHandoffCarrier(nonce);

      // Assert
      expect(build, throwsA(isA<ArgumentError>()));
    });

    test('parse gives null for an absent or malformed carrier', () {
      // Arrange
      const List<String?> carriers = <String?>[
        null,
        '',
        _nonce,
        'atomi-app-handoff:v2:$_nonce',
        'atomi-app-handoff:v1:AAAA',
        'atomi-app-handoff:v1:app-handoff:$_nonce',
        ' $_carrier',
      ];

      // Act
      final List<String?> nonces = carriers
          .map(parseAppHandoffCarrier)
          .toList();

      // Assert
      expect(nonces, everyElement(isNull));
    });

    test('parse gives the same answer as the 1.0.0 rule for every sample', () {
      // Arrange
      final List<String> carriers = <String>[
        for (final String s in _samples) 'atomi-app-handoff:v1:$s',
      ];

      // Act
      final List<String?> nonces = carriers
          .map(parseAppHandoffCarrier)
          .toList();

      // Assert
      expect(nonces, <String?>[
        for (final String s in _samples) _publishedRule(s) ? s : null,
      ]);
    });
  });

  group('install referrer', () {
    test('a single app_handoff field round-trips', () {
      // Arrange
      final String referrer = buildAppHandoffInstallReferrer(_nonce);

      // Act
      final String? nonce = parseAppHandoffInstallReferrer(referrer);

      // Assert
      expect(referrer, 'app_handoff=atomi-app-handoff%3Av1%3A$_nonce');
      expect(nonce, _nonce);
    });

    test('campaign fields are encoded after it and ignored when parsed', () {
      // Arrange
      final String referrer = buildAppHandoffInstallReferrer(
        _nonce,
        extraFields: <String, String>{'utm source': 'a&b', 'utm_medium': ''},
      );

      // Act
      final String? nonce = parseAppHandoffInstallReferrer(referrer);

      // Assert
      expect(
        referrer,
        'app_handoff=atomi-app-handoff%3Av1%3A$_nonce'
        '&utm+source=a%26b&utm_medium=',
      );
      expect(nonce, _nonce);
    });

    test('build throws an ArgumentError on an invalid nonce', () {
      // Arrange
      const String nonce = 'not-a-nonce';

      // Act
      void build() => buildAppHandoffInstallReferrer(nonce);

      // Assert
      expect(build, throwsA(isA<ArgumentError>()));
    });

    test('zero, duplicate or empty fields are absent', () {
      // Arrange
      const String field = 'app_handoff=atomi-app-handoff%3Av1%3A$_nonce';
      const List<String?> referrers = <String?>[
        null,
        '',
        'utm_source=play',
        '$field&$field',
        'app_handoff=',
        'app_handoff=$_nonce',
      ];

      // Act
      final List<String?> nonces = referrers
          .map(parseAppHandoffInstallReferrer)
          .toList();

      // Assert
      expect(nonces, everyElement(isNull));
    });

    test('empty pairs and pairs without a value are skipped', () {
      // Arrange
      const String referrer =
          '&utm_source&&app_handoff=atomi-app-handoff%3Av1%3A$_nonce&';

      // Act
      final String? nonce = parseAppHandoffInstallReferrer(referrer);

      // Assert
      expect(nonce, _nonce);
    });

    test('a bare app_handoff with no value counts as a second field', () {
      // Arrange
      const String referrer =
          'app_handoff&app_handoff=atomi-app-handoff%3Av1%3A$_nonce';

      // Act
      final String? nonce = parseAppHandoffInstallReferrer(referrer);

      // Assert
      expect(nonce, isNull);
    });

    test('a percent-encoded field name is decoded before matching', () {
      // Arrange
      const String referrer = 'app%5Fhandoff=atomi-app-handoff%3Av1%3A$_nonce';

      // Act
      final String? nonce = parseAppHandoffInstallReferrer(referrer);

      // Assert
      expect(nonce, _nonce);
    });

    test(
      'a malformed percent escape in the value is absent, never a throw',
      () {
        // Arrange
        const List<String> referrers = <String>[
          'app_handoff=%zz',
          'app_handoff=atomi-app-handoff%3Av1%3A$_nonce%C3%A',
          'app_handoff=%FF',
          'utm_source=play&app_handoff=%',
        ];

        // Act
        final List<String?> nonces = referrers
            .map(parseAppHandoffInstallReferrer)
            .toList();

        // Assert
        expect(nonces, everyElement(isNull));
      },
    );

    test('a malformed escape in another field name is ignored', () {
      // Arrange
      const String referrer =
          'utm%zz=1&app_handoff=atomi-app-handoff%3Av1%3A$_nonce';

      // Act
      final String? nonce = parseAppHandoffInstallReferrer(referrer);

      // Assert
      expect(nonce, _nonce);
    });
  });

  group('clipboard', () {
    test('trims leading and trailing ASCII space, tab, CR and LF', () {
      // Arrange
      const String contents = ' \t\r\n$_carrier\n\r\t ';

      // Act
      final String? nonce = parseAppHandoffClipboard(contents);

      // Assert
      expect(nonce, _nonce);
    });

    test('other whitespace is not trimmed, so the carrier is invalid', () {
      // Arrange
      const List<String> contents = <String>[
        ' $_carrier',
        '$_carrier\u000b',
        '$_carrier\u000c',
        ' $_carrier',
      ];

      // Act
      final List<String?> nonces = contents
          .map(parseAppHandoffClipboard)
          .toList();

      // Assert
      expect(nonces, everyElement(isNull));
    });

    test('absent, blank or malformed contents are absent', () {
      // Arrange
      const List<String?> contents = <String?>[
        null,
        '',
        '   ',
        'atomi-app-handoff:v1:AAAA',
        'hello',
      ];

      // Act
      final List<String?> nonces = contents
          .map(parseAppHandoffClipboard)
          .toList();

      // Assert
      expect(nonces, everyElement(isNull));
    });
  });
}
