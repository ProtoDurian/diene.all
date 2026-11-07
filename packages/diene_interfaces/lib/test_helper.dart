/// In-memory fakes for every port, with FIFO scripted results, and plain-throw
/// assertions; no test framework is imported.
library;

import 'dart:collection';
import 'dart:convert';

import 'package:diene_problems/diene_problems.dart';
import 'package:diene_result/diene_result.dart';

import 'diene_interfaces.dart';

final class InMemorySystem implements System {
  InMemorySystem({
    Map<String, String> environment = const <String, String>{},
    this.directory = '/',
    DateTime? now,
  }) : environmentVariables = Map<String, String>.of(environment),
       now = (now ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true))
           .toUtc();

  final Map<String, String> environmentVariables;

  final List<Duration> requestedDelays = <Duration>[];

  final Queue<Result<String?>> _environmentResults = Queue<Result<String?>>();
  final Queue<Result<String>> _directoryResults = Queue<Result<String>>();
  final Queue<Result<DateTime>> _clockResults = Queue<Result<DateTime>>();
  final Queue<Result<void>> _delayResults = Queue<Result<void>>();

  String directory;

  DateTime now;

  void enqueueEnvironmentResult(Result<String?> result) {
    _environmentResults.add(result);
  }

  void enqueueDirectoryResult(Result<String> result) {
    _directoryResults.add(result);
  }

  void enqueueClockResult(Result<DateTime> result) {
    _clockResults.add(result);
  }

  void enqueueDelayResult(Result<void> result) {
    _delayResults.add(result);
  }

  @override
  Result<String?> environment(String name) => _environmentResults.isNotEmpty
      ? _environmentResults.removeFirst()
      : Ok<String?>(environmentVariables[name]);

  @override
  Result<String> currentDirectory() => _directoryResults.isNotEmpty
      ? _directoryResults.removeFirst()
      : Ok<String>(directory);

  @override
  Result<DateTime> nowUtc() => _clockResults.isNotEmpty
      ? _clockResults.removeFirst()
      : Ok<DateTime>(now.toUtc());

  @override
  Future<Result<void>> delay(Duration duration) async {
    requestedDelays.add(duration);
    return _delayResults.isNotEmpty
        ? _delayResults.removeFirst()
        : const Ok<void>(null);
  }
}

/// A byte-backed [Vfs]; a scripted result replaces the real operation once.
final class InMemoryVfs implements Vfs {
  InMemoryVfs({
    Map<String, List<int>> files = const <String, List<int>>{},
    Iterable<String> directories = const <String>['/'],
    DateTime? modifiedAt,
  }) : _files = <String, List<int>>{
         for (final MapEntry<String, List<int>> entry in files.entries)
           normalizePath(entry.key): List<int>.of(entry.value),
       },
       _directories = <String>{
         '/',
         for (final String directory in directories) normalizePath(directory),
       },
       modifiedAt =
           (modifiedAt ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true))
               .toUtc() {
    for (final String path in _files.keys.toList()) {
      _createParents(_parent(path));
    }
  }

  final Map<String, List<int>> _files;
  final Set<String> _directories;
  final Queue<Result<bool>> _existsResults = Queue<Result<bool>>();
  final Queue<Result<VfsStat>> _statResults = Queue<Result<VfsStat>>();
  final Queue<Result<List<int>>> _readBytesResults = Queue<Result<List<int>>>();
  final Queue<Result<String>> _readTextResults = Queue<Result<String>>();
  final Queue<Result<void>> _writeBytesResults = Queue<Result<void>>();
  final Queue<Result<void>> _writeTextResults = Queue<Result<void>>();
  final Queue<Result<List<VfsEntry>>> _listResults =
      Queue<Result<List<VfsEntry>>>();
  final Queue<Result<void>> _createDirectoryResults = Queue<Result<void>>();
  final Queue<Result<void>> _deleteResults = Queue<Result<void>>();

  final DateTime modifiedAt;

  Map<String, List<int>> get files =>
      UnmodifiableMapView<String, List<int>>(<String, List<int>>{
        for (final MapEntry<String, List<int>> entry in _files.entries)
          entry.key: List<int>.unmodifiable(entry.value),
      });

  Set<String> get directories => Set<String>.unmodifiable(_directories);

  void enqueueExistsResult(Result<bool> result) => _existsResults.add(result);

  void enqueueStatResult(Result<VfsStat> result) => _statResults.add(result);

  void enqueueReadBytesResult(Result<List<int>> result) {
    _readBytesResults.add(result);
  }

  void enqueueReadTextResult(Result<String> result) {
    _readTextResults.add(result);
  }

  void enqueueWriteBytesResult(Result<void> result) {
    _writeBytesResults.add(result);
  }

  void enqueueWriteTextResult(Result<void> result) {
    _writeTextResults.add(result);
  }

  void enqueueListResult(Result<List<VfsEntry>> result) {
    _listResults.add(result);
  }

  void enqueueCreateDirectoryResult(Result<void> result) {
    _createDirectoryResults.add(result);
  }

  void enqueueDeleteResult(Result<void> result) {
    _deleteResults.add(result);
  }

  @override
  Future<Result<bool>> exists(String path) async {
    if (_existsResults.isNotEmpty) {
      return _existsResults.removeFirst();
    }
    final String normalized = normalizePath(path);
    return Ok<bool>(
      _files.containsKey(normalized) || _directories.contains(normalized),
    );
  }

  @override
  Future<Result<VfsStat>> stat(String path) async {
    if (_statResults.isNotEmpty) {
      return _statResults.removeFirst();
    }
    final String normalized = normalizePath(path);
    final List<int>? bytes = _files[normalized];
    if (bytes != null) {
      return Ok<VfsStat>(
        VfsStat(
          type: VfsEntryType.file,
          size: bytes.length,
          modifiedAt: modifiedAt,
        ),
      );
    }
    if (_directories.contains(normalized)) {
      return Ok<VfsStat>(
        VfsStat(type: VfsEntryType.directory, size: 0, modifiedAt: modifiedAt),
      );
    }
    return _notFound<VfsStat>('stat', normalized);
  }

  @override
  Future<Result<List<int>>> readBytes(String path) async {
    if (_readBytesResults.isNotEmpty) {
      return _readBytesResults.removeFirst();
    }
    final String normalized = normalizePath(path);
    final List<int>? bytes = _files[normalized];
    return bytes == null
        ? _notFound<List<int>>('readBytes', normalized)
        : Ok<List<int>>(List<int>.unmodifiable(bytes));
  }

  @override
  Future<Result<String>> readText(String path) async {
    if (_readTextResults.isNotEmpty) {
      return _readTextResults.removeFirst();
    }
    final String normalized = normalizePath(path);
    final List<int>? bytes = _files[normalized];
    return bytes == null
        ? _notFound<String>('readText', normalized)
        : Ok<String>(utf8.decode(bytes, allowMalformed: true));
  }

  @override
  Future<Result<void>> writeBytes(
    String path,
    List<int> bytes, {
    bool createParents = false,
  }) async {
    if (_writeBytesResults.isNotEmpty) {
      return _writeBytesResults.removeFirst();
    }
    return _write('writeBytes', path, bytes, createParents: createParents);
  }

  @override
  Future<Result<void>> writeText(
    String path,
    String content, {
    bool createParents = false,
  }) async {
    if (_writeTextResults.isNotEmpty) {
      return _writeTextResults.removeFirst();
    }
    return _write(
      'writeText',
      path,
      utf8.encode(content),
      createParents: createParents,
    );
  }

  @override
  Future<Result<List<VfsEntry>>> list(
    String path, {
    bool recursive = false,
  }) async {
    if (_listResults.isNotEmpty) {
      return _listResults.removeFirst();
    }
    final String normalized = normalizePath(path);
    if (!_directories.contains(normalized)) {
      return _notFound<List<VfsEntry>>('list', normalized);
    }
    final String prefix = normalized == '/' ? '/' : '$normalized/';
    final List<VfsEntry> entries = <VfsEntry>[
      for (final String directory in _directories)
        if (directory != normalized &&
            directory.startsWith(prefix) &&
            (recursive || !_relative(directory, prefix).contains('/')))
          VfsEntry(
            path: directory,
            type: VfsEntryType.directory,
            size: 0,
            modifiedAt: modifiedAt,
          ),
      for (final MapEntry<String, List<int>> file in _files.entries)
        if (file.key.startsWith(prefix) &&
            (recursive || !_relative(file.key, prefix).contains('/')))
          VfsEntry(
            path: file.key,
            type: VfsEntryType.file,
            size: file.value.length,
            modifiedAt: modifiedAt,
          ),
    ]..sort((VfsEntry left, VfsEntry right) => left.path.compareTo(right.path));
    return Ok<List<VfsEntry>>(List<VfsEntry>.unmodifiable(entries));
  }

  @override
  Future<Result<void>> createDirectory(
    String path, {
    bool recursive = false,
  }) async {
    if (_createDirectoryResults.isNotEmpty) {
      return _createDirectoryResults.removeFirst();
    }
    final String normalized = normalizePath(path);
    final String parent = _parent(normalized);
    if (!_directories.contains(parent) && !recursive) {
      return _notFound<void>('createDirectory', parent);
    }
    if (recursive) {
      _createParents(normalized);
    } else {
      _directories.add(normalized);
    }
    return const Ok<void>(null);
  }

  @override
  Future<Result<void>> delete(String path, {bool recursive = false}) async {
    if (_deleteResults.isNotEmpty) {
      return _deleteResults.removeFirst();
    }
    final String normalized = normalizePath(path);
    if (_files.remove(normalized) != null) {
      return const Ok<void>(null);
    }
    if (!_directories.contains(normalized)) {
      return _notFound<void>('delete', normalized);
    }
    final String prefix = normalized == '/' ? '/' : '$normalized/';
    final bool hasChildren =
        _files.keys.any((String key) => key.startsWith(prefix)) ||
        _directories.any(
          (String directory) =>
              directory != normalized && directory.startsWith(prefix),
        );
    if (hasChildren && !recursive) {
      return portFailure<void>(
        port: PortName.vfs,
        code: PortErrorCode.directoryNotEmpty,
        operation: 'delete',
        message: 'Directory not empty',
        details: <String, Object?>{'path': normalized},
      );
    }
    _files.removeWhere((String key, List<int> _) => key.startsWith(prefix));
    _directories.removeWhere(
      (String directory) =>
          directory == normalized || directory.startsWith(prefix),
    );
    _directories.add('/');
    return const Ok<void>(null);
  }

  Result<void> _write(
    String operation,
    String path,
    List<int> bytes, {
    required bool createParents,
  }) {
    final String normalized = normalizePath(path);
    final String parent = _parent(normalized);
    if (!_directories.contains(parent)) {
      if (!createParents) {
        return _notFound<void>(operation, parent);
      }
      _createParents(parent);
    }
    _files[normalized] = List<int>.of(bytes);
    return const Ok<void>(null);
  }

  void _createParents(String path) {
    if (path == '/') {
      _directories.add('/');
      return;
    }
    final List<String> segments = path.split('/')
      ..removeWhere((String segment) => segment.isEmpty);
    String current = '';
    for (final String segment in segments) {
      current = '$current/$segment';
      _directories.add(current);
    }
  }

  Err<T> _notFound<T>(String operation, String path) => portFailure<T>(
    port: PortName.vfs,
    code: PortErrorCode.notFound,
    operation: operation,
    message: 'Path not found',
    details: <String, Object?>{'path': path},
  );

  static String _relative(String path, String prefix) =>
      path.substring(prefix.length);

  static String _parent(String path) {
    final int separator = path.lastIndexOf('/');
    return separator <= 0 ? '/' : path.substring(0, separator);
  }

  /// Collapses empty segments and forces a leading slash.
  static String normalizePath(String path) {
    final Iterable<String> segments = path
        .split('/')
        .where((String part) => part.isNotEmpty);
    return '/${segments.join('/')}';
  }
}

/// An unscripted [run] fails with `unexpected_call`; every call is recorded.
final class InMemoryTerminal implements Terminal {
  InMemoryTerminal({
    this.interactive = true,
    List<String> input = const <String>[],
  }) : _input = Queue<String>.of(input);

  final List<TerminalCommand> commands = <TerminalCommand>[];

  final List<TerminalWrite> writes = <TerminalWrite>[];

  final List<TerminalRead> reads = <TerminalRead>[];

  final Queue<String> _input;
  final Queue<Result<TerminalOutput>> _results =
      Queue<Result<TerminalOutput>>();
  final Queue<Result<void>> _writeResults = Queue<Result<void>>();
  final Queue<Result<String?>> _readResults = Queue<Result<String?>>();

  @override
  final bool interactive;

  void enqueue(Result<TerminalOutput> result) => _results.add(result);

  void enqueueWriteResult(Result<void> result) => _writeResults.add(result);

  void enqueueReadResult(Result<String?> result) => _readResults.add(result);

  @override
  Future<Result<TerminalOutput>> run(TerminalCommand command) async {
    commands.add(command);
    return _results.isEmpty
        ? portFailure<TerminalOutput>(
            port: PortName.terminal,
            code: PortErrorCode.unexpectedCall,
            operation: 'run',
            message: 'Terminal result not scripted',
            details: <String, Object?>{'executable': command.executable},
          )
        : _results.removeFirst();
  }

  @override
  Future<Result<void>> write(TerminalWrite output) async {
    writes.add(output);
    return _writeResults.isNotEmpty
        ? _writeResults.removeFirst()
        : const Ok<void>(null);
  }

  @override
  Future<Result<String?>> readLine([
    TerminalRead input = const TerminalRead(),
  ]) async {
    reads.add(input);
    if (_readResults.isNotEmpty) {
      return _readResults.removeFirst();
    }
    return Ok<String?>(_input.isEmpty ? null : _input.removeFirst());
  }
}

final class InMemoryLoggerSink implements LoggerSink {
  final List<LogRecord> records = <LogRecord>[];

  final Queue<Result<void>> _results = Queue<Result<void>>();
  final Queue<Result<void>> _flushResults = Queue<Result<void>>();

  int flushCount = 0;

  void enqueue(Result<void> result) => _results.add(result);

  void enqueueFlushResult(Result<void> result) => _flushResults.add(result);

  @override
  Result<void> emit(LogRecord record) {
    if (_results.isNotEmpty) {
      return _results.removeFirst();
    }
    records.add(record);
    return const Ok<void>(null);
  }

  @override
  Future<Result<void>> flush() async {
    flushCount += 1;
    return _flushResults.isNotEmpty
        ? _flushResults.removeFirst()
        : const Ok<void>(null);
  }
}

final class InMemoryMetricsCollector implements MetricsCollector {
  final List<MetricRecord> records = <MetricRecord>[];

  final Queue<Result<void>> _results = Queue<Result<void>>();
  final Queue<Result<void>> _flushResults = Queue<Result<void>>();

  int flushCount = 0;

  void enqueue(Result<void> result) => _results.add(result);

  void enqueueFlushResult(Result<void> result) => _flushResults.add(result);

  @override
  Result<void> emit(MetricRecord record) {
    if (_results.isNotEmpty) {
      return _results.removeFirst();
    }
    records.add(record);
    return const Ok<void>(null);
  }

  @override
  Future<Result<void>> flush() async {
    flushCount += 1;
    return _flushResults.isNotEmpty
        ? _flushResults.removeFirst()
        : const Ok<void>(null);
  }
}

final class SeamAssertionFailure implements Exception {
  const SeamAssertionFailure(this.message);

  final String message;

  @override
  String toString() => 'SeamAssertionFailure: $message';
}

/// Throws [SeamAssertionFailure] unless [problem] matches [port] and [code].
Problem expectPortProblem(
  Problem problem, {
  required PortName port,
  required PortErrorCode code,
  String? operation,
}) {
  final Object? actualPort = problem.data['port'];
  final Object? actualCode = problem.data['code'];
  if (actualPort != port.name || actualCode != code.wireId) {
    throw SeamAssertionFailure(
      'Expected a ${port.name}/${code.wireId} problem, got '
      '$actualPort/$actualCode.',
    );
  }
  if (problem.status != code.status) {
    throw SeamAssertionFailure(
      'Expected status ${code.status} for ${code.wireId}, got '
      '${problem.status}.',
    );
  }
  if (problem.recoverable != code.recoverable) {
    throw SeamAssertionFailure(
      'Expected recoverable=${code.recoverable} for ${code.wireId}, got '
      '${problem.recoverable}.',
    );
  }
  if (operation != null && problem.data['operation'] != operation) {
    throw SeamAssertionFailure(
      'Expected operation "$operation", got "${problem.data['operation']}".',
    );
  }
  return problem;
}
