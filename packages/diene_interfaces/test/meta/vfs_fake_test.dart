import 'dart:convert';

import 'package:diene_interfaces/diene_interfaces.dart';
import 'package:diene_interfaces/test_helper.dart';
import 'package:diene_result/diene_result.dart';
import 'package:diene_result/test_helper.dart';
import 'package:test/test.dart';

InMemoryVfs _seeded() => InMemoryVfs(
  files: <String, List<int>>{
    '/a/one.txt': utf8.encode('one'),
    '/a/b/two.txt': utf8.encode('two'),
  },
  modifiedAt: DateTime.utc(2026, 7, 25),
);

void main() {
  group('InMemoryVfs seeding and normalisation', () {
    test('normalises seeded paths and materialises their parents', () async {
      // Arrange
      final InMemoryVfs vfs = InMemoryVfs(
        files: <String, List<int>>{'a//b/c.txt': utf8.encode('x')},
      );

      // Act
      final result = await vfs.exists('/a/b/c.txt');

      // Assert
      expect(expectOk(result), isTrue);
      expect(vfs.directories, containsAll(<String>['/', '/a', '/a/b']));
      expect(vfs.files.keys, <String>['/a/b/c.txt']);
    });

    test('collapses a blank path to the root', () {
      // Arrange
      const String blank = '';
      const String slashes = '//';
      const String relative = 'a/b';

      // Act
      final String blankPath = InMemoryVfs.normalizePath(blank);
      final String slashesPath = InMemoryVfs.normalizePath(slashes);
      final String relativePath = InMemoryVfs.normalizePath(relative);

      // Assert
      expect(blankPath, '/');
      expect(slashesPath, '/');
      expect(relativePath, '/a/b');
    });

    test('exposes deeply unmodifiable snapshots', () {
      // Arrange
      final InMemoryVfs vfs = _seeded();

      // Act
      final Map<String, List<int>> files = vfs.files;
      void clearFiles() => files.clear();
      void mutateBytes() => files['/a/one.txt']!.add(0);
      void addDirectory() => vfs.directories.add('/x');

      // Assert
      expect(clearFiles, throwsUnsupportedError);
      expect(mutateBytes, throwsUnsupportedError);
      expect(addDirectory, throwsUnsupportedError);
    });

    test('seeds extra directories', () async {
      // Arrange
      final InMemoryVfs vfs = InMemoryVfs(directories: <String>['/only']);

      // Act
      final present = await vfs.exists('/only');
      final absent = await vfs.exists('/absent');

      // Assert
      expect(expectOk(present), isTrue);
      expect(expectOk(absent), isFalse);
    });
  });

  group('InMemoryVfs reads', () {
    test(
      'reads bytes and text, and rejects a missing path as a value',
      () async {
        // Arrange
        final InMemoryVfs vfs = _seeded();

        // Act
        final bytesResult = await vfs.readBytes('/a/one.txt');
        final textResult = await vfs.readText('/a/b/two.txt');
        void mutate() => expectOk(bytesResult).add(0);
        final missingBytes = await vfs.readBytes('/absent');
        final missingText = await vfs.readText('/absent');

        // Assert
        expect(utf8.decode(expectOk(bytesResult)), 'one');
        expect(expectOk(textResult), 'two');
        expect(mutate, throwsUnsupportedError);
        expectPortProblem(
          expectErr(missingBytes),
          port: PortName.vfs,
          code: PortErrorCode.notFound,
          operation: 'readBytes',
        );
        expectPortProblem(
          expectErr(missingText),
          port: PortName.vfs,
          code: PortErrorCode.notFound,
          operation: 'readText',
        );
      },
    );

    test('decodes malformed bytes instead of throwing', () async {
      // Arrange
      final InMemoryVfs vfs = InMemoryVfs(
        files: <String, List<int>>{
          '/bad.bin': <int>[0xff, 0xfe],
        },
      );

      // Act
      final result = await vfs.readText('/bad.bin');

      // Assert
      expect(expectOk(result), isNotEmpty);
    });

    test('stats files, directories, and absent paths', () async {
      // Arrange
      final InMemoryVfs vfs = _seeded();

      // Act
      final fileResult = await vfs.stat('/a/one.txt');
      final directoryResult = await vfs.stat('/a');
      final absentResult = await vfs.stat('/absent');

      // Assert
      final VfsStat file = expectOk(fileResult);
      final VfsStat directory = expectOk(directoryResult);
      expect(file.type, VfsEntryType.file);
      expect(file.size, 3);
      expect(file.modifiedAt, DateTime.utc(2026, 7, 25));
      expect(directory.type, VfsEntryType.directory);
      expect(directory.size, 0);
      expectPortProblem(
        expectErr(absentResult),
        port: PortName.vfs,
        code: PortErrorCode.notFound,
        operation: 'stat',
      );
    });
  });

  group('InMemoryVfs writes', () {
    test('writes bytes and text into an existing directory', () async {
      // Arrange
      final InMemoryVfs vfs = _seeded();

      // Act
      final writeBytesResult = await vfs.writeBytes('/a/three.bin', <int>[
        1,
        2,
      ]);
      final writeTextResult = await vfs.writeText('/a/four.txt', 'four');
      final readBytesResult = await vfs.readBytes('/a/three.bin');
      final readTextResult = await vfs.readText('/a/four.txt');

      // Assert
      expectOk(writeBytesResult);
      expectOk(writeTextResult);
      expect(expectOk(readBytesResult), <int>[1, 2]);
      expect(expectOk(readTextResult), 'four');
    });

    test('refuses a missing parent unless createParents is set', () async {
      // Arrange
      final InMemoryVfs vfs = _seeded();

      // Act
      final missingBytes = await vfs.writeBytes('/new/deep/x.bin', <int>[1]);
      final missingText = await vfs.writeText('/new/deep/x.txt', 'x');
      final created = await vfs.writeText(
        '/new/deep/x.txt',
        'x',
        createParents: true,
      );

      // Assert
      expectPortProblem(
        expectErr(missingBytes),
        port: PortName.vfs,
        code: PortErrorCode.notFound,
        operation: 'writeBytes',
      );
      expectPortProblem(
        expectErr(missingText),
        port: PortName.vfs,
        code: PortErrorCode.notFound,
        operation: 'writeText',
      );
      expectOk(created);
      expect(vfs.directories, containsAll(<String>['/new', '/new/deep']));
    });

    test('copies written bytes so the caller cannot mutate storage', () async {
      // Arrange
      final InMemoryVfs vfs = InMemoryVfs();
      final List<int> bytes = <int>[1];

      // Act
      final writeResult = await vfs.writeBytes('/x.bin', bytes);
      bytes.add(2);
      final readResult = await vfs.readBytes('/x.bin');

      // Assert
      expectOk(writeResult);
      expect(expectOk(readResult), <int>[1]);
    });
  });

  group('InMemoryVfs listing', () {
    test('lists a directory shallowly and recursively, sorted', () async {
      // Arrange
      final InMemoryVfs vfs = _seeded();

      // Act
      final shallowResult = await vfs.list('/a');
      final deepResult = await vfs.list('/a', recursive: true);
      void mutate() {
        final List<VfsEntry> entries = expectOk(shallowResult);
        entries.add(entries.first);
      }

      // Assert
      final List<VfsEntry> shallow = expectOk(shallowResult);
      final List<VfsEntry> deep = expectOk(deepResult);
      expect(shallow.map((VfsEntry entry) => entry.path), <String>[
        '/a/b',
        '/a/one.txt',
      ]);
      expect(deep.map((VfsEntry entry) => entry.path), <String>[
        '/a/b',
        '/a/b/two.txt',
        '/a/one.txt',
      ]);
      expect(shallow.first.type, VfsEntryType.directory);
      expect(mutate, throwsUnsupportedError);
    });

    test('lists the root', () async {
      // Arrange
      final InMemoryVfs vfs = InMemoryVfs(
        files: <String, List<int>>{'/top.txt': utf8.encode('t')},
      );

      // Act
      final result = await vfs.list('/');

      // Assert
      expect(expectOk(result).map((VfsEntry entry) => entry.path), <String>[
        '/top.txt',
      ]);
    });

    test('rejects listing an unknown directory as a value', () async {
      // Arrange
      final InMemoryVfs vfs = InMemoryVfs();

      // Act
      final result = await vfs.list('/absent');

      // Assert
      expectPortProblem(
        expectErr(result),
        port: PortName.vfs,
        code: PortErrorCode.notFound,
        operation: 'list',
      );
    });
  });

  group('InMemoryVfs directory creation and deletion', () {
    test('creates a directory beside an existing parent', () async {
      // Arrange
      final InMemoryVfs vfs = _seeded();

      // Act
      final result = await vfs.createDirectory('/a/c');

      // Assert
      expectOk(result);
      expect(vfs.directories, contains('/a/c'));
    });

    test('refuses a missing parent unless recursive', () async {
      // Arrange
      final InMemoryVfs vfs = InMemoryVfs();

      // Act
      final rejected = await vfs.createDirectory('/x/y');
      final accepted = await vfs.createDirectory('/x/y', recursive: true);

      // Assert
      expectPortProblem(
        expectErr(rejected),
        port: PortName.vfs,
        code: PortErrorCode.notFound,
        operation: 'createDirectory',
      );
      expectOk(accepted);
      expect(vfs.directories, containsAll(<String>['/x', '/x/y']));
    });

    test('deletes a file, and reports an unknown path as a value', () async {
      // Arrange
      final InMemoryVfs vfs = _seeded();

      // Act
      final deleted = await vfs.delete('/a/one.txt');
      final exists = await vfs.exists('/a/one.txt');
      final absent = await vfs.delete('/a/one.txt');

      // Assert
      expectOk(deleted);
      expect(expectOk(exists), isFalse);
      expectPortProblem(
        expectErr(absent),
        port: PortName.vfs,
        code: PortErrorCode.notFound,
        operation: 'delete',
      );
    });

    test('refuses a non-empty directory unless recursive', () async {
      // Arrange
      final InMemoryVfs vfs = _seeded();

      // Act
      final first = await vfs.delete('/a');
      final second = await vfs.delete('/a');
      final deleted = await vfs.delete('/a', recursive: true);
      final directoryExists = await vfs.exists('/a');
      final fileExists = await vfs.exists('/a/b/two.txt');

      // Assert
      expectPortProblem(
        expectErr(second),
        port: PortName.vfs,
        code: PortErrorCode.directoryNotEmpty,
        operation: 'delete',
      );
      expect(expectErr(first), isNotNull);
      expectOk(deleted);
      expect(expectOk(directoryExists), isFalse);
      expect(expectOk(fileExists), isFalse);
      expect(vfs.directories, <String>{'/'});
    });

    test('deletes an empty directory without the recursive flag', () async {
      // Arrange
      final InMemoryVfs vfs = InMemoryVfs(directories: <String>['/empty']);

      // Act
      final result = await vfs.delete('/empty');

      // Assert
      expectOk(result);
      expect(vfs.directories, <String>{'/'});
    });
  });

  group('InMemoryVfs scripted results', () {
    test('every fallible member honours one scripted answer', () async {
      // Arrange
      final InMemoryVfs vfs = _seeded()
        ..enqueueExistsResult(const Ok<bool>(true))
        ..enqueueStatResult(
          const Ok<VfsStat>(VfsStat(type: VfsEntryType.link, size: 0)),
        )
        ..enqueueReadBytesResult(const Ok<List<int>>(<int>[9]))
        ..enqueueReadTextResult(const Ok<String>('scripted'))
        ..enqueueWriteBytesResult(const Ok<void>(null))
        ..enqueueWriteTextResult(const Ok<void>(null))
        ..enqueueListResult(const Ok<List<VfsEntry>>(<VfsEntry>[]))
        ..enqueueCreateDirectoryResult(const Ok<void>(null))
        ..enqueueDeleteResult(const Ok<void>(null));

      // Act
      final exists = await vfs.exists('/whatever');
      final stat = await vfs.stat('/whatever');
      final bytes = await vfs.readBytes('/whatever');
      final text = await vfs.readText('/whatever');
      final writeBytes = await vfs.writeBytes('/nowhere/x', <int>[1]);
      final writeText = await vfs.writeText('/nowhere/x', 'x');
      final list = await vfs.list('/nowhere');
      final create = await vfs.createDirectory('/nowhere/deep');
      final delete = await vfs.delete('/nowhere');
      final absent = await vfs.exists('/absent');

      // Assert
      expect(expectOk(exists), isTrue);
      expect(expectOk(stat).type, VfsEntryType.link);
      expect(expectOk(bytes), <int>[9]);
      expect(expectOk(text), 'scripted');
      expectOk(writeBytes);
      expectOk(writeText);
      expect(expectOk(list), isEmpty);
      expectOk(create);
      expectOk(delete);
      expect(expectOk(absent), isFalse);
    });
  });
}
