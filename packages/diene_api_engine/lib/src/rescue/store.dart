import 'dart:io';

/// Durable key/value store for pins, last-known-good and cached docs.
abstract interface class RescueStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

/// An in-memory store; the default when no disk is wired.
class InMemoryRescueStore implements RescueStore {
  InMemoryRescueStore([Map<String, String>? seed])
    : _data = <String, String>{...?seed};

  final Map<String, String> _data;

  @override
  Future<String?> read(String key) async => _data[key];

  @override
  Future<void> write(String key, String value) async => _data[key] = value;

  @override
  Future<void> delete(String key) async => _data.remove(key);
}

/// A `dart:io` store: one file per key under [directory].
class FileRescueStore implements RescueStore {
  FileRescueStore(this.directory);

  final Directory directory;

  File _file(String key) {
    final String safe = key.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    return File('${directory.path}/rescue_$safe.txt');
  }

  @override
  Future<String?> read(String key) async {
    final File file = _file(key);
    return file.existsSync() ? file.readAsString() : null;
  }

  @override
  Future<void> write(String key, String value) async {
    await directory.create(recursive: true);
    await _file(key).writeAsString(value);
  }

  @override
  Future<void> delete(String key) async {
    final File file = _file(key);
    if (file.existsSync()) {
      await file.delete();
    }
  }
}
