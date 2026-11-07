import 'dart:convert';
import 'dart:io';

const String ianaArchivePath =
    '../../third_party/iana-tzdata-2026b/tzdata2026b.tar.gz';

// backzone is left out: it only adds pre-1970 history to existing zones.
const List<String> ianaZoneDefiningFiles = <String>[
  'africa',
  'antarctica',
  'asia',
  'australasia',
  'europe',
  'northamerica',
  'southamerica',
  'etcetera',
  'factory',
  'backward',
];

class IanaSource {
  const IanaSource({required this.release, required this.identifiers});

  final String release;
  final List<String> identifiers;
}

/// Regular files of a tar.gz archive, by member name.
Map<String, List<int>> readTarGz(List<int> archive) {
  final List<int> tar = gzip.decode(archive);
  final Map<String, List<int>> files = <String, List<int>>{};
  int offset = 0;
  while (offset + 512 <= tar.length) {
    final List<int> header = tar.sublist(offset, offset + 512);
    if (header.every((int byte) => byte == 0)) {
      break;
    }
    final String name = _field(header, 0, 100);
    final String prefix = _field(header, 345, 155);
    final int size = int.parse(_field(header, 124, 12).trim(), radix: 8);
    final int type = header[156];
    final int start = offset + 512;
    if (type == 0x30 || type == 0) {
      final String path = prefix.isEmpty ? name : '$prefix/$name';
      files[path] = tar.sublist(start, start + size);
    }
    offset = start + (size + 511) ~/ 512 * 512;
  }
  return files;
}

String _field(List<int> header, int start, int length) {
  final List<int> raw = header.sublist(start, start + length);
  final int end = raw.indexOf(0);
  return ascii.decode(end == -1 ? raw : raw.sublist(0, end));
}

/// Release and sorted `Zone`/`Link` names of the archive at [archivePath].
///
/// Throws [ArgumentError] when the archive or a required member is missing.
IanaSource extractIanaSource(String archivePath) {
  final File file = File(archivePath);
  if (!file.existsSync()) {
    throw ArgumentError('IANA archive not found: $archivePath');
  }
  final Map<String, List<int>> files = readTarGz(file.readAsBytesSync());
  final String release = utf8.decode(_member(files, 'version')).trim();

  final Set<String> ids = <String>{};
  for (final String name in ianaZoneDefiningFiles) {
    for (final String line in const LineSplitter().convert(
      utf8.decode(_member(files, name)),
    )) {
      final List<String> fields = line.split(RegExp(r'\s+'));
      switch (fields.first) {
        case 'Zone':
          if (fields.length >= 2) {
            ids.add(fields[1]);
          }
        case 'Link':
          if (fields.length >= 3) {
            ids.add(fields[2]);
          }
      }
    }
  }

  final List<String> sorted = ids.toList()..sort();
  return IanaSource(release: release, identifiers: sorted);
}

List<int> _member(Map<String, List<int>> files, String name) {
  final List<int>? bytes = files[name];
  if (bytes == null) {
    throw ArgumentError('IANA archive has no member: $name');
  }
  return bytes;
}
