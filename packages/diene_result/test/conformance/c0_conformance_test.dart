import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:diene_result/diene_result.dart';
import 'package:test/test.dart';

const String _fixturesPath = 'test/fixtures/c0';

List<Object?> _roundTripResult(List<Object?> wire) =>
    Result<Object?>.fromSerial(
      wire,
      decodeOk: (Object? value) => value,
    ).serial();

List<Object?> _roundTripOption(List<Object?> wire) =>
    Option<Object?>.fromSerial(
      wire,
      decodeSome: (Object? value) => value,
    ).serial();

final Map<String, List<Object?> Function(List<Object?>)> _valid =
    <String, List<Object?> Function(List<Object?>)>{
      'err_problem_no_detail.json': _roundTripResult,
      'ok_object.json': _roundTripResult,
      'some_object.json': _roundTripOption,
    };

final Map<String, List<Object?> Function(List<Object?>)> _invalid =
    <String, List<Object?> Function(List<Object?>)>{
      'err_not_object.json': _roundTripResult,
      'err_problem_string_status.json': _roundTripResult,
      'some_three_items.json': _roundTripOption,
    };

void main() {
  final Map<String, Object?> manifest =
      (jsonDecode(File('$_fixturesPath/manifest.json').readAsStringSync())!
              as Map<Object?, Object?>)
          .cast<String, Object?>();
  final Map<String, Object?> fixtures =
      (manifest['fixtures']! as Map<Object?, Object?>).cast<String, Object?>();

  test('manifest is local, sha256 and pins exactly the checked fixtures', () {
    // Arrange
    final Set<String> checked = <String>{..._valid.keys, ..._invalid.keys};

    // Act
    final Set<String> pinned = fixtures.keys.toSet();

    // Assert
    expect(manifest['authority'], 'local-regression-only');
    expect(manifest['algorithm'], 'sha256');
    expect(pinned, checked);
  });

  group('wire fixtures', () {
    fixtures.forEach((String name, Object? digest) {
      test(name, () {
        // Arrange
        final List<int> bytes = File('$_fixturesPath/$name').readAsBytesSync();
        final List<Object?> wire =
            jsonDecode(utf8.decode(bytes))! as List<Object?>;

        // Act
        final String actualDigest = sha256.convert(bytes).toString();

        // Assert
        expect(
          actualDigest,
          digest,
          reason: 'fixture "$name" digest drifted from the manifest',
        );
        if (_valid[name] case final roundTrip?) {
          expect(roundTrip(wire), wire);
        } else {
          expect(() => _invalid[name]!(wire), throwsFormatException);
        }
      });
    });
  });

  test('a problem without detail or instance omits them on the wire', () {
    // Arrange
    final List<Object?> wire =
        jsonDecode(
              File(
                '$_fixturesPath/err_problem_no_detail.json',
              ).readAsStringSync(),
            )!
            as List<Object?>;

    // Act
    final Map<Object?, Object?> encoded =
        _roundTripResult(wire)[1]! as Map<Object?, Object?>;

    // Assert
    expect(encoded.containsKey('detail'), isFalse);
    expect(encoded.containsKey('instance'), isFalse);
    expect(encoded.values, isNot(contains(null)));
  });
}
