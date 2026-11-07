import 'package:diene_core_utils/diene_core_utils.dart';
import 'package:diene_interfaces/diene_interfaces.dart';
import 'package:diene_interfaces/test_helper.dart';
import 'package:diene_problems/diene_problems.dart';
import 'package:diene_result/diene_result.dart';
import 'package:test/test.dart';

void main() {
  group('readVfsText / writeVfsText through the published Vfs seam', () {
    test('a write is readable back through the same seam', () async {
      // Arrange
      final InMemoryVfs vfs = InMemoryVfs();

      // Act
      final Result<void> written = await writeVfsText(
        vfs,
        '/etc/diene/base.yaml',
        'app:\n  name: base\n',
      );
      final Result<String> read = await readVfsText(
        vfs,
        '/etc/diene/base.yaml',
      );

      // Assert
      expect(written.isOk, isTrue, reason: _describe(written));
      expect(read.isOk, isTrue, reason: _describe(read));
      expect(read.unwrap(), 'app:\n  name: base\n');
    });

    test('writeVfsText creates missing parents', () async {
      // Arrange
      final InMemoryVfs vfs = InMemoryVfs();

      // Act
      final Result<void> written = await writeVfsText(
        vfs,
        '/deeply/nested/parents/config.yaml',
        'x: 1',
      );
      final Result<bool> exists = await vfs.exists(
        '/deeply/nested/parents/config.yaml',
      );

      // Assert
      expect(written.isOk, isTrue, reason: _describe(written));
      expect(exists.unwrap(), isTrue);
    });

    test("a seam failure is propagated UNCHANGED, not re-wrapped", () async {
      // Arrange
      final InMemoryVfs vfs = InMemoryVfs();

      // Act
      final Result<String> read = await readVfsText(vfs, '/absent.yaml');

      // Assert
      expect(read.isErr, isTrue);
      final Problem problem = read.unwrapErr();
      expect(problem.data['port'], 'vfs');
      expect(problem.data.containsKey('util'), isFalse);
      expect(problem.status, 404);
    });
  });

  group('readOptionalVfsText', () {
    test('absence is a successful null, not a failure', () async {
      // Arrange
      final InMemoryVfs vfs = InMemoryVfs();

      // Act
      final Result<String?> read = await readOptionalVfsText(
        vfs,
        '/absent.yaml',
      );

      // Assert
      expect(read.isOk, isTrue, reason: _describe(read));
      expect(read.unwrap(), isNull);
    });

    test('a present layer returns its text', () async {
      // Arrange
      final InMemoryVfs vfs = InMemoryVfs();
      (await writeVfsText(
        vfs,
        '/overlay.yaml',
        'app:\n  name: overlay\n',
      )).unwrap();

      // Act
      final Result<String?> read = await readOptionalVfsText(
        vfs,
        '/overlay.yaml',
      );

      // Assert
      expect(read.unwrap(), 'app:\n  name: overlay\n');
    });

    test('a non-absence failure from exists() still propagates', () async {
      // Arrange
      final InMemoryVfs vfs = InMemoryVfs()
        ..enqueueExistsResult(
          portFailure<bool>(
            port: PortName.vfs,
            code: PortErrorCode.permissionDenied,
            operation: "exists",
            message: "host refused",
          ),
        );

      // Act
      final Result<String?> read = await readOptionalVfsText(
        vfs,
        '/guarded.yaml',
      );

      // Assert
      expect(read.isErr, isTrue, reason: 'a permission error is not absence');
      expect(read.unwrapErr().status, 403);
    });

    test('a failure AFTER a positive exists() still propagates', () async {
      // Arrange
      final _RecordingVfs vfs = _RecordingVfs(
        existsResult: const Ok<bool>(true),
        readResult: Err<String>(
          _problem(PortErrorCode.io, 'read', 'device fell over'),
        ),
      );

      // Act
      final Result<String?> read = await readOptionalVfsText(
        vfs,
        '/flaky.yaml',
      );

      // Assert
      expect(read.isErr, isTrue);
      expect(read.unwrapErr().status, 500);
      expect(vfs.calls, <String>['exists:/flaky.yaml', 'readText:/flaky.yaml']);
    });
  });

  group('loadConfigLayers — the ladder over a real seam', () {
    test('layers merge in order with the later layer winning', () async {
      // Arrange
      final InMemoryVfs vfs = InMemoryVfs();
      (await writeVfsText(vfs, '/base.kv', 'name=base\nretries=1\n')).unwrap();
      (await writeVfsText(vfs, '/landscape.kv', 'retries=2\n')).unwrap();

      // Act
      final Result<JsonObject> loaded =
          await loadConfigLayers(vfs, <ConfigLayer>[
            const ConfigLayer(path: '/base.kv', parse: _parseKeyValue),
            const ConfigLayer(path: '/landscape.kv', parse: _parseKeyValue),
          ]);

      // Assert
      expect(loaded.isOk, isTrue, reason: _describe(loaded));
      expect(loaded.unwrap(), <String, Object?>{
        'name': 'base',
        'retries': '2',
      });
    });

    test('an absent OPTIONAL layer contributes nothing', () async {
      // Arrange
      final InMemoryVfs vfs = InMemoryVfs();
      (await writeVfsText(vfs, '/base.kv', 'name=base\n')).unwrap();

      // Act
      final Result<JsonObject> loaded =
          await loadConfigLayers(vfs, <ConfigLayer>[
            const ConfigLayer(path: '/base.kv', parse: _parseKeyValue),
            const ConfigLayer(
              path: '/never-written.kv',
              parse: _parseKeyValue,
              optional: true,
            ),
          ]);

      // Assert
      expect(loaded.unwrap(), <String, Object?>{'name': 'base'});
    });

    test('an absent REQUIRED layer fails with the seam envelope', () async {
      // Arrange
      final InMemoryVfs vfs = InMemoryVfs();

      // Act
      final Result<JsonObject> loaded = await loadConfigLayers(
        vfs,
        <ConfigLayer>[
          const ConfigLayer(path: '/required.kv', parse: _parseKeyValue),
        ],
      );

      // Assert
      expect(loaded.isErr, isTrue);
      expect(loaded.unwrapErr().data['port'], 'vfs');
      expect(loaded.unwrapErr().status, 404);
    });

    test('an optional layer whose exists() fails aborts the load', () async {
      // Arrange
      final InMemoryVfs vfs = InMemoryVfs()
        ..enqueueExistsResult(
          portFailure<bool>(
            port: PortName.vfs,
            code: PortErrorCode.unavailable,
            operation: "exists",
            message: "host unavailable",
          ),
        );

      // Act
      final Result<JsonObject> loaded = await loadConfigLayers(
        vfs,
        <ConfigLayer>[
          const ConfigLayer(
            path: '/overlay.kv',
            parse: _parseKeyValue,
            optional: true,
          ),
        ],
      );

      // Assert
      expect(loaded.isErr, isTrue);
      expect(loaded.unwrapErr().status, 503);
      expect(loaded.unwrapErr().recoverable, isTrue);
    });

    test('a parse failure aborts the load and is returned unchanged', () async {
      // Arrange
      final InMemoryVfs vfs = InMemoryVfs();
      (await writeVfsText(vfs, '/broken.kv', 'no-equals-sign\n')).unwrap();

      // Act
      final Result<JsonObject> loaded = await loadConfigLayers(
        vfs,
        <ConfigLayer>[
          const ConfigLayer(path: '/broken.kv', parse: _parseKeyValue),
        ],
      );

      // Assert
      expect(loaded.isErr, isTrue);
      expect(loaded.unwrapErr().title, 'malformed key=value line');
    });

    test(
      'no layer present at all is a core-utils failure, not a seam one',
      () async {
        // Arrange
        final InMemoryVfs vfs = InMemoryVfs();

        // Act
        final Result<JsonObject> loaded =
            await loadConfigLayers(vfs, <ConfigLayer>[
              const ConfigLayer(
                path: '/a.kv',
                parse: _parseKeyValue,
                optional: true,
              ),
              const ConfigLayer(
                path: '/b.kv',
                parse: _parseKeyValue,
                optional: true,
              ),
            ]);

        // Assert
        expect(loaded.isErr, isTrue);
        final Problem problem = loaded.unwrapErr();
        expect(problem.data['util'], 'vfs');
        expect(problem.data['code'], 'invalid_input');
        expect(problem.data['paths'], <String>['/a.kv', '/b.kv']);
        expect(problem.status, 400);
      },
    );

    test('an empty layer list reports the same no-layer failure', () async {
      // Arrange
      final InMemoryVfs vfs = InMemoryVfs();

      // Act
      final Result<JsonObject> loaded = await loadConfigLayers(
        vfs,
        <ConfigLayer>[],
      );

      // Assert
      expect(loaded.isErr, isTrue);
      expect(loaded.unwrapErr().data['paths'], <String>[]);
    });
  });

  group('interface-type injection (not a concrete implementation)', () {
    test(
      'an independent Vfs implementation drives the identical members',
      () async {
        // Arrange
        final _RecordingVfs vfs = _RecordingVfs(
          existsResult: const Ok<bool>(true),
          readResult: const Ok<String>('name=recorded\n'),
        );

        // Act
        final Result<String> read = await readVfsText(vfs, '/x.kv');
        final Result<String?> readOptional = await readOptionalVfsText(
          vfs,
          '/x.kv',
        );
        final Result<void> written = await writeVfsText(
          vfs,
          '/x.kv',
          'name=written\n',
        );
        final Result<JsonObject> loaded = await loadConfigLayers(
          vfs,
          <ConfigLayer>[
            const ConfigLayer(path: '/x.kv', parse: _parseKeyValue),
          ],
        );

        // Assert
        expect(read.unwrap(), 'name=recorded\n');
        expect(readOptional.unwrap(), 'name=recorded\n');
        expect(written.isOk, isTrue);
        expect(loaded.unwrap(), <String, Object?>{'name': 'recorded'});
        expect(vfs.calls, <String>[
          'readText:/x.kv',
          'exists:/x.kv',
          'readText:/x.kv',
          'writeText:/x.kv:createParents=true',
          'readText:/x.kv',
        ]);
      },
    );
  });
}

final class _RecordingVfs implements Vfs {
  _RecordingVfs({required this.existsResult, required this.readResult});

  final Result<bool> existsResult;
  final Result<String> readResult;
  final List<String> calls = <String>[];

  @override
  Future<Result<bool>> exists(String path) async {
    calls.add('exists:$path');
    return existsResult;
  }

  @override
  Future<Result<String>> readText(String path) async {
    calls.add('readText:$path');
    return readResult;
  }

  @override
  Future<Result<void>> writeText(
    String path,
    String content, {
    bool createParents = false,
  }) async {
    calls.add('writeText:$path:createParents=$createParents');
    return const Ok<void>(null);
  }

  @override
  Future<Result<VfsStat>> stat(String path) async =>
      _unsupported<VfsStat>('stat');

  @override
  Future<Result<List<int>>> readBytes(String path) async =>
      _unsupported<List<int>>('readBytes');

  @override
  Future<Result<void>> writeBytes(
    String path,
    List<int> bytes, {
    bool createParents = false,
  }) async => _unsupported<void>('writeBytes');

  @override
  Future<Result<List<VfsEntry>>> list(
    String path, {
    bool recursive = false,
  }) async => _unsupported<List<VfsEntry>>('list');

  @override
  Future<Result<void>> createDirectory(
    String path, {
    bool recursive = false,
  }) async => _unsupported<void>('createDirectory');

  @override
  Future<Result<void>> delete(String path, {bool recursive = false}) async =>
      _unsupported<void>('delete');

  Result<T> _unsupported<T>(String operation) => Err<T>(
    _problem(
      PortErrorCode.unsupported,
      operation,
      'not implemented in this fake',
    ),
  );
}

Problem _problem(PortErrorCode code, String operation, String message) =>
    portProblem(
      port: PortName.vfs,
      code: code,
      operation: operation,
      message: message,
    );

Result<JsonObject> _parseKeyValue(String text) {
  final JsonObject parsed = <String, Object?>{};
  for (final String line in text.split('\n')) {
    if (line.trim().isEmpty) {
      continue;
    }
    final int equals = line.indexOf('=');
    if (equals < 1) {
      return Err<JsonObject>(
        utilProblem(
          util: UtilName.vfs,
          code: UtilErrorCode.invalidFormat,
          operation: 'parseKeyValue',
          message: 'malformed key=value line',
          details: <String, Object?>{'line': line},
        ),
      );
    }
    parsed[line.substring(0, equals)] = line.substring(equals + 1);
  }
  return Ok<JsonObject>(parsed);
}

String _describe(Result<Object?> result) => result.match(
  ok: (Object? value) => 'ok($value)',
  err: (Problem problem) => 'err(${problem.title}: ${problem.detail})',
);
