import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:diene_core_utils/c0_temporal.dart';
import 'package:diene_core_utils/diene_core_utils.dart'
    show
        IanaTimezone,
        IsoDuration,
        WireCodec,
        WireDate,
        WireTime,
        ianaTimeZoneRelease,
        isIanaTimeZone,
        normalizeRfc3339ToUtc,
        parseRfc3339Utc,
        wireDateGrammar,
        wireDurationGrammar,
        wireInstantGrammar,
        wireTimeGrammar,
        wireTimezoneGrammar;
import 'package:diene_problems/diene_problems.dart';
import 'package:diene_result/diene_result.dart';
import 'package:test/test.dart';

const C0TemporalContract _contract = c0TemporalContract;
const WireCodec _codec = WireCodec();

const Set<String> _grammars = <String>{
  wireDateGrammar,
  wireTimeGrammar,
  wireInstantGrammar,
  wireDurationGrammar,
  wireTimezoneGrammar,
};

void _expectWireProblem(
  Result<Object?> result,
  String rejected, {
  String? grammar,
}) {
  expect(result.isErr, isTrue, reason: '$rejected was accepted');
  final Problem problem = result.unwrapErr();
  final Map<String, Object?> data = problem.data;
  expect(problem.status, 400);
  expect(problem.recoverable, isFalse);
  expect(data['util'], 'wire');
  expect(data['code'], 'invalid_format');
  // Impossible components report their own grammar, not the outer one.
  expect(data['expected'], grammar ?? isIn(_grammars));
  expect(problem.title, 'expected ${data['expected']}');
  expect(data['value'], rejected);
  expect(problem.type, endsWith('/v1/wire_invalid_format'));
}

void main() {
  group('contract provenance', () {
    test('the recorded digest matches the vectors', () {
      // Arrange
      final String payload = _contract.digestPayload();

      // Act
      final String digest = sha256.convert(utf8.encode(payload)).toString();

      // Assert
      expect(digest, _contract.provenance.contentSha256);
    });

    test('provenance names the source and the bundled IANA release', () {
      // Arrange
      const C0TemporalProvenance provenance = C0TemporalProvenance(
        contractVersion: '1',
        c0Section: 'Serialization',
        c0Source: 'C0 contracts',
        ianaRelease: ianaTimeZoneRelease,
        ianaArchiveUrl:
            'https://data.iana.org/time-zones/releases/tzdata2026b.tar.gz',
        ianaArchiveSha256:
            '114543d9f19a6bfeb5bca43686aea173d38755a3db1f2eec112647ae92c6f544',
        contentSha256: '',
      );

      // Act
      final C0TemporalProvenance actual = _contract.provenance;

      // Assert
      expect(actual.contractVersion, provenance.contractVersion);
      expect(actual.c0Section, provenance.c0Section);
      expect(actual.c0Source, provenance.c0Source);
      expect(actual.ianaRelease, provenance.ianaRelease);
      expect(actual.ianaArchiveUrl, provenance.ianaArchiveUrl);
      expect(actual.ianaArchiveSha256, provenance.ianaArchiveSha256);
    });

    test('every vector list has cases', () {
      // Arrange
      final Map<String, C0Cases> domains = <String, C0Cases>{
        'dates': _contract.dates,
        'times': _contract.times,
        'durations': _contract.durations,
        'timezones': _contract.timezones,
      };

      // Act
      final List<String> empty = <String>[
        for (final MapEntry<String, C0Cases> entry in domains.entries)
          if (entry.value.valid.isEmpty || entry.value.invalid.isEmpty)
            entry.key,
      ];

      // Assert
      expect(empty, isEmpty);
      expect(_contract.instants, isNotEmpty);
      expect(_contract.invalidInstants, isNotEmpty);
    });
  });

  group('calendar dates', () {
    test('valid cases round-trip through the wire form', () {
      // Arrange
      final List<String> valid = _contract.dates.valid;

      // Act
      final List<Result<WireDate>> parsed = valid.map(WireDate.parse).toList();

      // Assert
      for (int i = 0; i < valid.length; i += 1) {
        expect(parsed[i].isOk, isTrue, reason: valid[i]);
        expect(_codec.encodeDate(parsed[i].unwrap()), valid[i]);
        expect(_codec.decodeDate(valid[i]).unwrap(), parsed[i].unwrap());
      }
    });

    test('invalid cases are problems, never throws', () {
      // Arrange
      final List<String> invalid = _contract.dates.invalid;

      // Act
      final List<Result<WireDate>> parsed = invalid
          .map(WireDate.parse)
          .toList();

      // Assert
      for (int i = 0; i < invalid.length; i += 1) {
        _expectWireProblem(parsed[i], invalid[i]);
      }
    });
  });

  group('wall-clock times', () {
    test('valid cases round-trip through the wire form', () {
      // Arrange
      final List<String> valid = _contract.times.valid;

      // Act
      final List<Result<WireTime>> parsed = valid.map(WireTime.parse).toList();

      // Assert
      for (int i = 0; i < valid.length; i += 1) {
        expect(parsed[i].isOk, isTrue, reason: valid[i]);
        expect(_codec.encodeTime(parsed[i].unwrap()), valid[i]);
        expect(_codec.decodeTime(valid[i]).unwrap(), parsed[i].unwrap());
      }
    });

    test('invalid cases are problems', () {
      // Arrange
      final List<String> invalid = _contract.times.invalid;

      // Act
      final List<Result<WireTime>> parsed = invalid
          .map(WireTime.parse)
          .toList();

      // Assert
      for (int i = 0; i < invalid.length; i += 1) {
        _expectWireProblem(parsed[i], invalid[i]);
      }
    });
  });

  group('durations', () {
    test('valid designations are kept as written', () {
      // Arrange
      final List<String> valid = _contract.durations.valid;

      // Act
      final List<Result<IsoDuration>> parsed = valid
          .map(IsoDuration.parse)
          .toList();

      // Assert
      for (int i = 0; i < valid.length; i += 1) {
        expect(parsed[i].isOk, isTrue, reason: valid[i]);
        expect(_codec.encodeDuration(parsed[i].unwrap()), valid[i]);
      }
    });

    test('invalid designations are problems', () {
      // Arrange
      final List<String> invalid = _contract.durations.invalid;

      // Act
      final List<Result<IsoDuration>> parsed = invalid
          .map(IsoDuration.parse)
          .toList();

      // Assert
      for (int i = 0; i < invalid.length; i += 1) {
        _expectWireProblem(parsed[i], invalid[i], grammar: wireDurationGrammar);
      }
    });
  });

  group('IANA timezone identifiers', () {
    test('legacy ids and aliases are valid, PST is not', () {
      // Arrange
      final List<String> valid = _contract.timezones.valid;

      // Act
      final List<Result<IanaTimezone>> parsed = valid
          .map(IanaTimezone.parse)
          .toList();

      // Assert
      expect(valid, containsAll(<String>['EST', 'GMT', 'US/Eastern']));
      expect(_contract.timezones.invalid, contains('PST'));
      for (int i = 0; i < valid.length; i += 1) {
        expect(parsed[i].isOk, isTrue, reason: valid[i]);
        expect(_codec.encodeTimezone(parsed[i].unwrap()), valid[i]);
        expect(isIanaTimeZone(valid[i]), isTrue);
      }
    });

    test('offsets, wrong case, traversal and unknown names are rejected', () {
      // Arrange
      final List<String> invalid = _contract.timezones.invalid;

      // Act
      final List<Result<IanaTimezone>> parsed = invalid
          .map(IanaTimezone.parse)
          .toList();

      // Assert
      for (int i = 0; i < invalid.length; i += 1) {
        _expectWireProblem(parsed[i], invalid[i], grammar: wireTimezoneGrammar);
        expect(isIanaTimeZone(invalid[i]), isFalse);
      }
    });
  });

  group('instants', () {
    test('every vector normalises to its canonical UTC form', () {
      // Arrange
      final List<C0InstantVector> vectors = _contract.instants;

      // Act
      final List<Result<String>> normalized = <Result<String>>[
        for (final C0InstantVector vector in vectors)
          normalizeRfc3339ToUtc(vector.input),
      ];

      // Assert
      for (int i = 0; i < vectors.length; i += 1) {
        final String canonical = vectors[i].canonicalUtc;
        expect(normalized[i].unwrap(), canonical);
        final DateTime reparsed = parseRfc3339Utc(canonical).unwrap();
        expect(reparsed.isUtc, isTrue);
        expect(_codec.encodeInstant(reparsed).unwrap(), canonical);
      }
    });

    test('the strict parser rejects every other spelling', () {
      // Arrange
      final List<String> invalid = _contract.invalidInstants;

      // Act
      final List<Result<DateTime>> parsed = invalid
          .map(parseRfc3339Utc)
          .toList();

      // Assert
      expect(invalid, contains('2026-07-21T01:02:03+00:00'));
      for (int i = 0; i < invalid.length; i += 1) {
        _expectWireProblem(parsed[i], invalid[i]);
      }
    });

    test('an offset is accepted only by the normalising helper', () {
      // Arrange
      const String offset = '2026-07-21T09:02:03+08:00';

      // Act
      final Result<DateTime> strict = _codec.decodeInstant(offset);
      final Result<String> normalized = _codec.normalizeInstant(offset);

      // Assert
      expect(parseRfc3339Utc(offset).isErr, isTrue);
      expect(strict.isErr, isTrue);
      expect(normalized.unwrap(), '2026-07-21T01:02:03.000Z');
    });
  });
}
