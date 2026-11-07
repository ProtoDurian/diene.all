import 'package:diene_interfaces/diene_interfaces.dart';
import 'package:diene_problems/diene_problems.dart';
import 'package:diene_result/test_helper.dart';
import 'package:test/test.dart';

void main() {
  group('VfsEntry', () {
    test('describes a file entry', () {
      // Arrange
      final DateTime modifiedAt = DateTime.utc(2026, 7, 25);

      // Act
      final VfsEntry entry = VfsEntry(
        path: '/a/b.txt',
        type: VfsEntryType.file,
        size: 12,
        modifiedAt: modifiedAt,
      );

      // Assert
      expect(entry.path, '/a/b.txt');
      expect(entry.type, VfsEntryType.file);
      expect(entry.size, 12);
      expect(entry.modifiedAt, DateTime.utc(2026, 7, 25));
      expect(entry.toString(), 'VfsEntry(/a/b.txt, file, 12)');
    });

    test('omits a modified instant when the host reports none', () {
      // Arrange
      const String path = '/link';

      // Act
      const VfsEntry entry = VfsEntry(
        path: path,
        type: VfsEntryType.link,
        size: 0,
      );

      // Assert
      expect(entry.modifiedAt, isNull);
      expect(VfsEntryType.values, hasLength(3));
    });
  });

  group('VfsStat', () {
    test('describes a directory without listing its parent', () {
      // Arrange
      const VfsEntryType type = VfsEntryType.directory;

      // Act
      const VfsStat stat = VfsStat(type: type, size: 0);

      // Assert
      expect(stat.type, VfsEntryType.directory);
      expect(stat.size, 0);
      expect(stat.modifiedAt, isNull);
      expect(stat.toString(), 'VfsStat(directory, 0)');
    });
  });

  group('checkVfsPath', () {
    test('accepts an absolute path', () {
      // Arrange
      const String path = '/etc/hosts';

      // Act
      final result = checkVfsPath(path);

      // Assert
      expect(expectOk(result), '/etc/hosts');
    });

    test('rejects a blank path', () {
      // Arrange
      const String path = '   ';

      // Act
      final result = checkVfsPath(path);

      // Assert
      final Problem problem = expectErr(result);
      expect(problem.status, 400);
      expect(problem.data['field'], 'path');
      expect(problem.data['operation'], 'path');
    });

    test('rejects a NUL-bearing path', () {
      // Arrange
      final String path = '/a${String.fromCharCode(0)}b';

      // Act
      final result = checkVfsPath(path, operation: 'readText');

      // Assert
      final Problem problem = expectErr(result);
      expect(problem.data['operation'], 'readText');
      expect(problem.title, 'Path must not contain a NUL byte');
    });

    test('rejects a relative path', () {
      // Arrange
      const String path = 'relative/file';

      // Act
      final result = checkVfsPath(path);

      // Assert
      final Problem problem = expectErr(result);
      expect(problem.title, 'Path must be absolute');
    });
  });
}
