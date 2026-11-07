import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:diene_core_utils/diene_core_utils.dart';
import 'package:test/test.dart';

import '../../tool/gen_iana_zones.dart';
import '../../tool/iana_source.dart';

const String _allowlistPath = 'lib/src/iana_zones.dart';

void main() {
  test('the vendored archive is the pinned official IANA release', () {
    // Arrange
    final File archive = File(ianaArchivePath);

    // Act
    final String digest = sha256.convert(archive.readAsBytesSync()).toString();

    // Assert
    expect(digest, c0TemporalContract.provenance.ianaArchiveSha256);
    expect(
      c0TemporalContract.provenance.ianaArchiveUrl,
      endsWith('/tzdata${c0TemporalContract.provenance.ianaRelease}.tar.gz'),
    );
  });

  test('the committed allowlist is exactly what the archive generates', () {
    // Arrange
    final IanaSource source = extractIanaSource(ianaArchivePath);

    // Act
    final String rendered = renderIanaZones(source);

    // Assert
    expect(source.identifiers.length, 598);
    expect(File(_allowlistPath).readAsStringSync(), rendered);
    for (final String id in <String>['Asia/Singapore', 'UTC', 'US/Eastern']) {
      expect(source.identifiers, contains(id));
      expect(isIanaTimeZone(id), isTrue, reason: id);
    }
    expect(isIanaTimeZone('Area/NotAnIanaZone'), isFalse);
  });

  test('release pins agree across archive, runtime and contract', () {
    // Arrange
    final IanaSource source = extractIanaSource(ianaArchivePath);

    // Act
    final String release = source.release;

    // Assert
    expect(release, '2026b');
    expect(release, ianaTimeZoneRelease);
    expect(release, c0TemporalContract.provenance.ianaRelease);
  });

  test('extraction rejects a missing archive and missing members', () {
    // Arrange
    final Directory scratch = Directory.systemTemp.createTempSync('iana');
    addTearDown(() => scratch.deleteSync(recursive: true));
    final File empty = File('${scratch.path}/empty.tar.gz')
      ..writeAsBytesSync(gzip.encode(List<int>.filled(1024, 0)));

    // Act
    Object? missingArchive;
    Object? missingMember;
    try {
      extractIanaSource('${scratch.path}/absent.tar.gz');
    } on ArgumentError catch (error) {
      missingArchive = error;
    }
    try {
      extractIanaSource(empty.path);
    } on ArgumentError catch (error) {
      missingMember = error;
    }

    // Assert
    expect(missingArchive, isA<ArgumentError>());
    expect(missingMember, isA<ArgumentError>());
    expect(readTarGz(empty.readAsBytesSync()), isEmpty);
  });
}
