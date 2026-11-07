import 'package:diene_result/diene_result.dart';

import 'port_problem.dart';

enum VfsEntryType { file, directory, link }

final class VfsEntry {
  const VfsEntry({
    required this.path,
    required this.type,
    required this.size,
    this.modifiedAt,
  });

  final String path;

  final VfsEntryType type;

  /// `0` for directories and links.
  final int size;

  final DateTime? modifiedAt;

  @override
  String toString() => 'VfsEntry($path, ${type.name}, $size)';
}

final class VfsStat {
  const VfsStat({required this.type, required this.size, this.modifiedAt});

  final VfsEntryType type;

  /// `0` for directories and links.
  final int size;

  final DateTime? modifiedAt;

  @override
  String toString() => 'VfsStat(${type.name}, $size)';
}

/// A filesystem port; path normalisation is left to each implementation.
abstract interface class Vfs {
  Future<Result<bool>> exists(String path);

  Future<Result<VfsStat>> stat(String path);

  Future<Result<List<int>>> readBytes(String path);

  /// Reads the file as UTF-8.
  Future<Result<String>> readText(String path);

  Future<Result<void>> writeBytes(
    String path,
    List<int> bytes, {
    bool createParents = false,
  });

  /// Writes the file as UTF-8.
  Future<Result<void>> writeText(
    String path,
    String content, {
    bool createParents = false,
  });

  Future<Result<List<VfsEntry>>> list(String path, {bool recursive = false});

  Future<Result<void>> createDirectory(String path, {bool recursive = false});

  Future<Result<void>> delete(String path, {bool recursive = false});
}

/// Rejects blank, NUL-bearing and relative paths before they reach a host.
Result<String> checkVfsPath(String path, {String operation = 'path'}) {
  if (path.trim().isEmpty) {
    return invalidInput<String>(
      port: PortName.vfs,
      operation: operation,
      field: 'path',
      message: 'Path must be non-blank',
    );
  }
  if (path.codeUnits.contains(0)) {
    return invalidInput<String>(
      port: PortName.vfs,
      operation: operation,
      field: 'path',
      message: 'Path must not contain a NUL byte',
    );
  }
  if (!path.startsWith('/')) {
    return invalidInput<String>(
      port: PortName.vfs,
      operation: operation,
      field: 'path',
      message: 'Path must be absolute',
    );
  }
  return Ok<String>(path);
}
