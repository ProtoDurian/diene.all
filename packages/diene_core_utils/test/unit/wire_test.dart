import 'package:diene_core_utils/diene_core_utils.dart';
import 'package:diene_result/diene_result.dart';
import 'package:test/test.dart';

void main() {
  const WireCodec codec = WireCodec();

  group('WireDate', () {
    test('of() validates the components', () {
      // Arrange
      const List<List<int>> parts = <List<int>>[
        <int>[2026, 7, 26],
        <int>[2000, 2, 29],
      ];

      // Act
      final List<String> rendered = parts
          .map(
            (List<int> p) => WireDate.of(p[0], p[1], p[2]).unwrap().toString(),
          )
          .toList();

      // Assert
      expect(rendered, <String>['2026-07-26', '2000-02-29']);
    });

    test('of() rejects an impossible calendar date', () {
      // Arrange
      final List<List<int>> partsList = <List<int>>[
        <int>[2026, 2, 30],
        <int>[2026, 13, 1],
        <int>[2026, 0, 1],
        <int>[2026, 1, 32],
        <int>[2026, 1, 0],
        <int>[1900, 2, 29],
      ];

      // Act
      final List<Result<WireDate>> dates = partsList
          .map((List<int> p) => WireDate.of(p[0], p[1], p[2]))
          .toList();

      // Assert
      for (int i = 0; i < partsList.length; i++) {
        expect(dates[i].isErr, isTrue, reason: '${partsList[i]} was accepted');
        expect(dates[i].unwrapErr().data['util'], 'wire');
      }
    });

    test('of() rejects a year outside 1..9999', () {
      // Arrange
      final List<int> badYears = <int>[0, -1, 10000];

      // Act
      final List<Result<WireDate>> rejected = badYears
          .map((int year) => WireDate.of(year, 1, 1))
          .toList();

      // Assert
      for (final Result<WireDate> result in rejected) {
        expect(result.isErr, isTrue);
      }
    });

    test('of() accepts the first and last year', () {
      // Arrange
      const int firstYear = 1;
      const int lastYear = 9999;

      // Act
      final WireDate first = WireDate.of(firstYear, 1, 1).unwrap();
      final WireDate last = WireDate.of(lastYear, 12, 31).unwrap();

      // Assert
      expect(first.toString(), '0001-01-01');
      expect(last.toString(), '9999-12-31');
    });

    test('components are exposed and zero-padded on the wire', () {
      // Arrange
      final Result<WireDate> built = WireDate.of(7, 1, 2);

      // Act
      final WireDate date = built.unwrap();

      // Assert
      expect(date.year, 7);
      expect(date.month, 1);
      expect(date.day, 2);
      expect(date.toString(), '0007-01-02');
    });

    test('equality and hashCode are structural', () {
      // Arrange
      final WireDate a = WireDate.parse('2026-07-26').unwrap();
      final WireDate b = WireDate.of(2026, 7, 26).unwrap();
      final Object notADate = '2026-07-26';

      // Act
      final bool nextDay = a == WireDate.of(2026, 7, 27).unwrap();
      final bool nextMonth = a == WireDate.of(2026, 8, 26).unwrap();
      final bool nextYear = a == WireDate.of(2027, 7, 26).unwrap();
      final bool otherType = a == notADate;

      // Assert
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(nextDay, isFalse);
      expect(nextMonth, isFalse);
      expect(nextYear, isFalse);
      expect(otherType, isFalse);
    });

    test('parse() rejects a shape mismatch before validating components', () {
      // Arrange
      const String raw = '2026-7-1';

      // Act
      final Result<WireDate> parsed = WireDate.parse(raw);

      // Assert
      expect(parsed.unwrapErr().data['expected'], wireDateGrammar);
      expect(parsed.unwrapErr().data['operation'], 'WireDate.parse');
    });
  });

  group('WireTime', () {
    test('of() validates the components', () {
      // Arrange
      const List<List<int>> parts = <List<int>>[
        <int>[0, 0, 0],
        <int>[23, 59, 59],
      ];

      // Act
      final List<String> rendered = parts
          .map(
            (List<int> p) => WireTime.of(p[0], p[1], p[2]).unwrap().toString(),
          )
          .toList();

      // Assert
      expect(rendered, <String>['00:00:00', '23:59:59']);
    });

    test('of() rejects out-of-range components', () {
      // Arrange
      final List<List<int>> partsList = <List<int>>[
        <int>[24, 0, 0],
        <int>[-1, 0, 0],
        <int>[0, 60, 0],
        <int>[0, -1, 0],
        <int>[0, 0, 60],
        <int>[0, 0, -1],
      ];

      // Act
      final List<Result<WireTime>> times = partsList
          .map((List<int> p) => WireTime.of(p[0], p[1], p[2]))
          .toList();

      // Assert
      for (int i = 0; i < partsList.length; i++) {
        expect(times[i].isErr, isTrue, reason: '${partsList[i]} was accepted');
      }
    });

    test('there is no leap second on the wire', () {
      // Arrange
      const String raw = '23:59:60';

      // Act
      final Result<WireTime> parsed = WireTime.parse(raw);

      // Assert
      expect(parsed.isErr, isTrue);
    });

    test('components are exposed', () {
      // Arrange
      final Result<WireTime> built = WireTime.of(1, 2, 3);

      // Act
      final WireTime time = built.unwrap();

      // Assert
      expect(<int>[time.hour, time.minute, time.second], <int>[1, 2, 3]);
    });

    test('equality is structural', () {
      // Arrange
      final WireTime time = WireTime.of(1, 2, 3).unwrap();
      final WireTime parsed = WireTime.parse('01:02:03').unwrap();
      final Object notATime = 3;

      // Act
      final bool nextSecond = time == WireTime.of(1, 2, 4).unwrap();
      final bool nextMinute = time == WireTime.of(1, 3, 3).unwrap();
      final bool nextHour = time == WireTime.of(2, 2, 3).unwrap();
      final bool otherType = time == notATime;

      // Assert
      expect(time, parsed);
      expect(time.hashCode, parsed.hashCode);
      expect(nextSecond, isFalse);
      expect(nextMinute, isFalse);
      expect(nextHour, isFalse);
      expect(otherType, isFalse);
    });
  });

  group('IsoDuration', () {
    test('a decimal comma is normalised to a point', () {
      // Arrange
      const String seconds = 'PT0,5S';
      const String hours = 'P1DT2,5H';

      // Act
      final IsoDuration parsedSeconds = IsoDuration.parse(seconds).unwrap();
      final IsoDuration parsedHours = IsoDuration.parse(hours).unwrap();

      // Assert
      expect(parsedSeconds.value, 'PT0.5S');
      expect(parsedHours.toString(), 'P1DT2.5H');
    });

    test('calendar units are preserved rather than converted', () {
      // Arrange
      const String raw = 'P1Y2M3W4D';

      // Act
      final IsoDuration parsed = IsoDuration.parse(raw).unwrap();

      // Assert
      expect(parsed.value, 'P1Y2M3W4D');
    });

    test('equality is structural over the normalised value', () {
      // Arrange
      final IsoDuration comma = IsoDuration.parse('PT0,5S').unwrap();
      final IsoDuration point = IsoDuration.parse('PT0.5S').unwrap();
      final IsoDuration other = IsoDuration.parse('PT1S').unwrap();
      final Object notADuration = 'PT0.5S';

      // Act
      final bool differentValue = comma == other;
      final bool otherType = comma == notADuration;

      // Assert
      expect(comma, point);
      expect(comma.hashCode, point.hashCode);
      expect(differentValue, isFalse);
      expect(otherType, isFalse);
    });

    test('a designation with no components is rejected', () {
      // Arrange
      final List<String> bad = <String>['P', 'PT', 'PW', '', 'T1H', '1DT2H'];

      // Act
      final List<Result<IsoDuration>> results = bad
          .map(IsoDuration.parse)
          .toList();

      // Assert
      for (int i = 0; i < bad.length; i++) {
        expect(results[i].isErr, isTrue, reason: '${bad[i]} was accepted');
      }
    });
  });

  group('IanaTimezone', () {
    test('membership comes from the vendored release, not the host', () {
      // Arrange
      const String singapore = 'Asia/Singapore';
      const String buenosAires = 'America/Argentina/Buenos_Aires';

      // Act
      final IanaTimezone parsedSingapore = IanaTimezone.parse(
        singapore,
      ).unwrap();
      final IanaTimezone parsedBuenosAires = IanaTimezone.parse(
        buenosAires,
      ).unwrap();
      final Result<IanaTimezone> etcUtc = IanaTimezone.parse('Etc/UTC');
      final Result<IanaTimezone> utc = IanaTimezone.parse('UTC');

      // Assert
      expect(parsedSingapore.value, 'Asia/Singapore');
      expect(parsedBuenosAires.toString(), 'America/Argentina/Buenos_Aires');
      expect(etcUtc.isOk, isTrue);
      expect(utc.isOk, isTrue);
    });

    test('equality is structural', () {
      // Arrange
      final IanaTimezone a = IanaTimezone.parse('UTC').unwrap();
      final IanaTimezone same = IanaTimezone.parse('UTC').unwrap();
      final IanaTimezone other = IanaTimezone.parse('Etc/UTC').unwrap();
      final Object notAZone = 'UTC';

      // Act
      final bool differentValue = a == other;
      final bool otherType = a == notAZone;

      // Assert
      expect(a, same);
      expect(a.hashCode, same.hashCode);
      expect(differentValue, isFalse);
      expect(otherType, isFalse);
    });

    test('path traversal is rejected as a plain non-member', () {
      // Arrange
      final List<String> traversals = <String>[
        'Area/../Location',
        '../../etc/passwd',
      ];

      // Act
      final List<Result<IanaTimezone>> results = traversals
          .map(IanaTimezone.parse)
          .toList();

      // Assert
      for (final Result<IanaTimezone> result in results) {
        expect(result.isErr, isTrue);
      }
    });
  });

  group('formatRfc3339Utc', () {
    test('a local DateTime is normalised to UTC rather than rejected', () {
      // Arrange
      final DateTime local = DateTime.utc(2026, 7, 26, 1, 2, 3).toLocal();

      // Act
      final Result<String> formatted = formatRfc3339Utc(local);

      // Assert
      expect(formatted.unwrap(), '2026-07-26T01:02:03.000Z');
    });

    test('sub-second precision survives', () {
      // Arrange
      final DateTime instant = DateTime.utc(2026, 7, 26, 1, 2, 3, 456);

      // Act
      final Result<String> formatted = formatRfc3339Utc(instant);

      // Assert
      expect(formatted.unwrap(), '2026-07-26T01:02:03.456Z');
    });

    test('a year with no RFC 3339 representation is rejected', () {
      // Arrange
      final List<DateTime> instants = <DateTime>[
        DateTime.utc(0, 1, 1),
        DateTime.utc(-1, 1, 1),
        DateTime.utc(10000, 1, 1),
      ];

      // Act
      final List<Result<String>> results = instants
          .map(formatRfc3339Utc)
          .toList();

      // Assert
      for (final Result<String> result in results) {
        expect(result.isErr, isTrue);
      }
    });
  });

  group('normalizeRfc3339ToUtc', () {
    test('an offset instant becomes the canonical Z form', () {
      // Arrange
      final List<String> instants = <String>[
        '2026-07-26T09:02:03+08:00',
        '2026-07-25T20:02:03-05:00',
        '2026-07-26T01:02:03+0000',
      ];

      // Act
      final List<String> normalized = instants
          .map((String s) => normalizeRfc3339ToUtc(s).unwrap())
          .toList();

      // Assert
      expect(normalized, <String>[
        '2026-07-26T01:02:03.000Z',
        '2026-07-26T01:02:03.000Z',
        '2026-07-26T01:02:03.000Z',
      ]);
    });

    test(
      'an already-canonical instant is idempotent, including lowercase z',
      () {
        // Arrange
        final List<String> instants = <String>[
          '2026-07-26T01:02:03Z',
          '2026-07-26T01:02:03z',
        ];

        // Act
        final List<String> normalized = instants
            .map((String s) => normalizeRfc3339ToUtc(s).unwrap())
            .toList();

        // Assert
        expect(normalized, <String>[
          '2026-07-26T01:02:03.000Z',
          '2026-07-26T01:02:03.000Z',
        ]);
      },
    );

    test('an instant with NO zone designator is rejected', () {
      // Arrange
      const String raw = '2026-07-26T01:02:03';

      // Act
      final Result<String> normalized = normalizeRfc3339ToUtc(raw);

      // Assert
      expect(normalized.isErr, isTrue);
      expect(normalized.unwrapErr().data['operation'], 'normalizeRfc3339ToUtc');
    });

    test('unparseable input is rejected', () {
      // Arrange
      final List<String> inputs = <String>['not-a-date', ''];

      // Act
      final List<Result<String>> results = inputs
          .map(normalizeRfc3339ToUtc)
          .toList();

      // Assert
      for (final Result<String> result in results) {
        expect(result.isErr, isTrue);
      }
    });

    test('a normalised value out of RFC 3339 range still fails', () {
      // Arrange
      const String raw = '0000-01-01T00:00:00Z';

      // Act
      final Result<String> normalized = normalizeRfc3339ToUtc(raw);

      // Assert
      expect(normalized.isErr, isTrue);
    });
  });

  group('parseRfc3339Utc', () {
    test('the returned DateTime is always UTC', () {
      // Arrange
      const String raw = '2026-07-26T01:02:03Z';

      // Act
      final DateTime parsed = parseRfc3339Utc(raw).unwrap();

      // Assert
      expect(parsed.isUtc, isTrue);
      expect(parsed, DateTime.utc(2026, 7, 26, 1, 2, 3));
    });

    test('an invalid TIME inside a well-shaped instant is rejected', () {
      // Arrange
      const String raw = '2026-07-26T24:00:00Z';

      // Act
      final Result<DateTime> parsed = parseRfc3339Utc(raw);

      // Assert
      expect(parsed.isErr, isTrue);
      expect(parsed.unwrapErr().data['expected'], wireTimeGrammar);
    });

    test('an invalid DATE inside a well-shaped instant is rejected', () {
      // Arrange
      const String raw = '2026-02-30T01:02:03Z';

      // Act
      final Result<DateTime> parsed = parseRfc3339Utc(raw);

      // Assert
      expect(parsed.isErr, isTrue);
      expect(parsed.unwrapErr().data['expected'], wireDateGrammar);
    });
  });

  group('WireCodec facade', () {
    test('every member delegates to the documented surface', () {
      // Arrange
      final WireDate date = WireDate.of(2026, 7, 26).unwrap();
      final WireTime time = WireTime.of(1, 2, 3).unwrap();
      final IsoDuration duration = IsoDuration.parse('P1W').unwrap();
      final IanaTimezone zone = IanaTimezone.parse('Asia/Singapore').unwrap();
      final DateTime instant = DateTime.utc(2026, 7, 26, 1, 2, 3);

      // Act
      final String encodedDate = codec.encodeDate(date);
      final WireDate decodedDate = codec.decodeDate('2026-07-26').unwrap();
      final String encodedTime = codec.encodeTime(time);
      final WireTime decodedTime = codec.decodeTime('01:02:03').unwrap();
      final String encodedDuration = codec.encodeDuration(duration);
      final IsoDuration decodedDuration = codec.decodeDuration('P1W').unwrap();
      final String encodedZone = codec.encodeTimezone(zone);
      final IanaTimezone decodedZone = codec
          .decodeTimezone('Asia/Singapore')
          .unwrap();
      final String encodedInstant = codec.encodeInstant(instant).unwrap();
      final DateTime decodedInstant = codec
          .decodeInstant('2026-07-26T01:02:03Z')
          .unwrap();
      final String normalizedInstant = codec
          .normalizeInstant('2026-07-26T09:02:03+08:00')
          .unwrap();

      // Assert
      expect(encodedDate, '2026-07-26');
      expect(decodedDate, date);
      expect(encodedTime, '01:02:03');
      expect(decodedTime, time);
      expect(encodedDuration, 'P1W');
      expect(decodedDuration, duration);
      expect(encodedZone, 'Asia/Singapore');
      expect(decodedZone, zone);
      expect(encodedInstant, '2026-07-26T01:02:03.000Z');
      expect(decodedInstant, instant);
      expect(normalizedInstant, '2026-07-26T01:02:03.000Z');
    });

    test('failures surface through the facade unchanged', () {
      // Arrange
      final DateTime unrepresentable = DateTime.utc(0, 1, 1);

      // Act
      final List<Result<Object?>> results = <Result<Object?>>[
        codec.decodeDate('nope'),
        codec.decodeTime('nope'),
        codec.decodeDuration('nope'),
        codec.decodeTimezone('PST'),
        codec.decodeInstant('nope'),
        codec.normalizeInstant('nope'),
        codec.encodeInstant(unrepresentable),
      ];

      // Assert
      for (final Result<Object?> result in results) {
        expect(result.isErr, isTrue);
      }
    });

    test('the facade is a const value, so injecting it costs nothing', () {
      // Arrange
      const WireCodec built = WireCodec();

      // Act
      final Object value = built;

      // Assert
      expect(value, isA<WireCodec>());
    });
  });

  group('grammar constants', () {
    test('each names its own domain and is used in that domain only', () {
      // Arrange
      final Map<String, Result<Object?>> byGrammar = <String, Result<Object?>>{
        wireDateGrammar: WireDate.parse('nope'),
        wireTimeGrammar: WireTime.parse('nope'),
        wireDurationGrammar: IsoDuration.parse('nope'),
        wireTimezoneGrammar: IanaTimezone.parse('nope'),
        wireInstantGrammar: parseRfc3339Utc('nope'),
      };

      // Act
      final Map<String, Object?> expectedByGrammar = <String, Object?>{
        for (final MapEntry<String, Result<Object?>> entry in byGrammar.entries)
          entry.key: entry.value.unwrapErr().data['expected'],
      };

      // Assert
      expect(byGrammar.keys.toSet(), hasLength(5), reason: 'grammars collide');
      expectedByGrammar.forEach((String grammar, Object? expected) {
        expect(expected, grammar);
      });
    });
  });
}
