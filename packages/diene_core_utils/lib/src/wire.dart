library;

import 'package:diene_problems/diene_problems.dart';
import 'package:diene_result/diene_result.dart';

import 'iana_zones.dart';
import 'util_problem.dart';

final RegExp _datePattern = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$');
final RegExp _timePattern = RegExp(r'^(\d{2}):(\d{2}):(\d{2})$');
final RegExp _instantPattern = RegExp(
  r'^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.\d+)?Z$',
);
final RegExp _durationPattern = RegExp(
  r'^P(?=\d|T\d)(?:(?:\d+(?:[.,]\d+)?Y)?(?:\d+(?:[.,]\d+)?M)?(?:\d+(?:[.,]\d+)?W)?(?:\d+(?:[.,]\d+)?D)?)(?:T(?=\d)(?:\d+(?:[.,]\d+)?H)?(?:\d+(?:[.,]\d+)?M)?(?:\d+(?:[.,]\d+)?S)?)?$',
);

const String wireDateGrammar = 'a YYYY-MM-DD calendar date';

const String wireTimeGrammar = 'an HH:mm:ss wall-clock time';

const String wireInstantGrammar = 'an RFC 3339 UTC instant ending in Z';

const String wireDurationGrammar = 'an ISO 8601 duration';

const String wireTimezoneGrammar = 'an IANA timezone identifier';

final class WireDate {
  const WireDate._(this.year, this.month, this.day);

  static Result<WireDate> of(int year, int month, int day) =>
      _build(year, month, day, '$year-$month-$day', 'WireDate.of');

  static Result<WireDate> parse(String value) {
    final RegExpMatch? match = _datePattern.firstMatch(value);
    if (match == null) {
      return invalidWireFormat<WireDate>(
        operation: 'WireDate.parse',
        expected: wireDateGrammar,
        value: value,
      );
    }
    return _build(
      int.parse(match.group(1)!),
      int.parse(match.group(2)!),
      int.parse(match.group(3)!),
      value,
      'WireDate.parse',
    );
  }

  static Result<WireDate> _build(
    int year,
    int month,
    int day,
    String source,
    String operation,
  ) => _validateDate(
    year,
    month,
    day,
    source,
    operation,
  ).map((void _) => WireDate._(year, month, day));

  final int year;

  final int month;

  final int day;

  @override
  String toString() => '${_pad(year, 4)}-${_pad(month, 2)}-${_pad(day, 2)}';

  @override
  bool operator ==(Object other) =>
      other is WireDate &&
      other.year == year &&
      other.month == month &&
      other.day == day;

  @override
  int get hashCode => Object.hash(year, month, day);
}

final class WireTime {
  const WireTime._(this.hour, this.minute, this.second);

  static Result<WireTime> of(int hour, int minute, int second) =>
      _build(hour, minute, second, '$hour:$minute:$second', 'WireTime.of');

  static Result<WireTime> parse(String value) {
    final RegExpMatch? match = _timePattern.firstMatch(value);
    if (match == null) {
      return invalidWireFormat<WireTime>(
        operation: 'WireTime.parse',
        expected: wireTimeGrammar,
        value: value,
      );
    }
    return _build(
      int.parse(match.group(1)!),
      int.parse(match.group(2)!),
      int.parse(match.group(3)!),
      value,
      'WireTime.parse',
    );
  }

  static Result<WireTime> _build(
    int hour,
    int minute,
    int second,
    String source,
    String operation,
  ) => _validateTime(
    hour,
    minute,
    second,
    source,
    operation,
  ).map((void _) => WireTime._(hour, minute, second));

  final int hour;

  final int minute;

  final int second;

  @override
  String toString() => '${_pad(hour, 2)}:${_pad(minute, 2)}:${_pad(second, 2)}';

  @override
  bool operator ==(Object other) =>
      other is WireTime &&
      other.hour == hour &&
      other.minute == minute &&
      other.second == second;

  @override
  int get hashCode => Object.hash(hour, minute, second);
}

/// Kept as written, decimal comma as point; never turned into a [Duration].
final class IsoDuration {
  const IsoDuration._(this.value);

  static Result<IsoDuration> parse(String value) {
    if (!_durationPattern.hasMatch(value)) {
      return invalidWireFormat<IsoDuration>(
        operation: 'IsoDuration.parse',
        expected: wireDurationGrammar,
        value: value,
      );
    }
    return Ok<IsoDuration>(IsoDuration._(value.replaceAll(',', '.')));
  }

  final String value;

  @override
  String toString() => value;

  @override
  bool operator ==(Object other) =>
      other is IsoDuration && other.value == value;

  @override
  int get hashCode => value.hashCode;
}

/// Exact membership in the bundled IANA release, not host data.
final class IanaTimezone {
  const IanaTimezone._(this.value);

  static Result<IanaTimezone> parse(String value) {
    if (!isIanaTimeZone(value)) {
      return invalidWireFormat<IanaTimezone>(
        operation: 'IanaTimezone.parse',
        expected: wireTimezoneGrammar,
        value: value,
      );
    }
    return Ok<IanaTimezone>(IanaTimezone._(value));
  }

  final String value;

  @override
  String toString() => value;

  @override
  bool operator ==(Object other) =>
      other is IanaTimezone && other.value == value;

  @override
  int get hashCode => value.hashCode;
}

/// Converts to UTC first; a year outside 1..9999 is `invalid_format`.
Result<String> formatRfc3339Utc(DateTime value) {
  final DateTime utc = value.toUtc();
  return _validateDate(
    utc.year,
    utc.month,
    utc.day,
    utc.toIso8601String(),
    'formatRfc3339Utc',
  ).map((void _) => utc.toIso8601String());
}

/// Accepts only `Z`; use [normalizeRfc3339ToUtc] for numeric offsets.
Result<DateTime> parseRfc3339Utc(String value) {
  final RegExpMatch? match = _instantPattern.firstMatch(value);
  if (match == null) {
    return invalidWireFormat<DateTime>(
      operation: 'parseRfc3339Utc',
      expected: wireInstantGrammar,
      value: value,
    );
  }
  final Result<void> date = _validateDate(
    int.parse(match.group(1)!),
    int.parse(match.group(2)!),
    int.parse(match.group(3)!),
    value,
    'parseRfc3339Utc',
  );
  if (date case Err<void>(problem: final Problem problem)) {
    return Err<DateTime>(problem);
  }
  final Result<void> time = _validateTime(
    int.parse(match.group(4)!),
    int.parse(match.group(5)!),
    int.parse(match.group(6)!),
    value,
    'parseRfc3339Utc',
  );
  if (time case Err<void>(problem: final Problem problem)) {
    return Err<DateTime>(problem);
  }
  return Ok<DateTime>(DateTime.parse(value).toUtc());
}

/// An RFC 3339 instant with `Z` or an offset, in the canonical UTC form.
Result<String> normalizeRfc3339ToUtc(String value) {
  final DateTime? parsed = DateTime.tryParse(value);
  if (parsed == null || !_hasExplicitZoneDesignator(value)) {
    return invalidWireFormat<String>(
      operation: 'normalizeRfc3339ToUtc',
      expected: 'an RFC 3339 instant with a Z or numeric offset designator',
      value: value,
    );
  }
  return formatRfc3339Utc(parsed);
}

final class WireCodec {
  const WireCodec();

  String encodeDate(WireDate value) => value.toString();

  Result<WireDate> decodeDate(String value) => WireDate.parse(value);

  String encodeTime(WireTime value) => value.toString();

  Result<WireTime> decodeTime(String value) => WireTime.parse(value);

  Result<String> encodeInstant(DateTime value) => formatRfc3339Utc(value);

  Result<DateTime> decodeInstant(String value) => parseRfc3339Utc(value);

  Result<String> normalizeInstant(String value) => normalizeRfc3339ToUtc(value);

  String encodeDuration(IsoDuration value) => value.toString();

  Result<IsoDuration> decodeDuration(String value) => IsoDuration.parse(value);

  String encodeTimezone(IanaTimezone value) => value.toString();

  Result<IanaTimezone> decodeTimezone(String value) =>
      IanaTimezone.parse(value);
}

bool _hasExplicitZoneDesignator(String value) =>
    value.endsWith('Z') ||
    value.endsWith('z') ||
    RegExp(r'[+-]\d{2}:?\d{2}$').hasMatch(value);

Result<void> _validateDate(
  int year,
  int month,
  int day,
  String source,
  String operation,
) {
  if (year < 1 || year > 9999) {
    return invalidWireFormat<void>(
      operation: operation,
      expected: wireDateGrammar,
      value: source,
    );
  }
  final DateTime date = DateTime.utc(year, month, day);
  if (date.year != year || date.month != month || date.day != day) {
    return invalidWireFormat<void>(
      operation: operation,
      expected: wireDateGrammar,
      value: source,
    );
  }
  return const Ok<void>(null);
}

Result<void> _validateTime(
  int hour,
  int minute,
  int second,
  String source,
  String operation,
) {
  if (hour < 0 ||
      hour > 23 ||
      minute < 0 ||
      minute > 59 ||
      second < 0 ||
      second > 59) {
    return invalidWireFormat<void>(
      operation: operation,
      expected: wireTimeGrammar,
      value: source,
    );
  }
  return const Ok<void>(null);
}

String _pad(int value, int width) => value.toString().padLeft(width, '0');
