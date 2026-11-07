import { describe, expect, it } from 'bun:test';
import {
  BumpError,
  bumpPath,
  bumpPreset,
  bumpPresetNames,
  normalizeVersion,
} from '../../../src/lib/release/bump-presets';

function apply(type: Parameters<typeof bumpPreset>[0], path: string, content: string, version = '2.0.0'): string {
  return bumpPreset(type).apply(path, content, version).content;
}

describe('bump presets', () => {
  describe('shared rules', () => {
    it('should REFUSE to create an absent field rather than write one', () => {
      // Arrange
      const content = '{\n  "name": "thing"\n}\n';

      // Act
      const act = () => apply('node-version', 'package.json', content);

      // Assert
      expect(act).toThrow(BumpError);
      expect(act).toThrow(/declares no .*version/);
      expect(act).toThrow(/package\.json/);
    });

    it('should REFUSE an ambiguous field rather than take the first match', () => {
      // Arrange
      const content = '<Project>\n  <Version>1.0.0</Version>\n  <Version>1.0.0</Version>\n</Project>\n';

      // Act
      const act = () => apply('dotnet-version', 'Version.props', content);

      // Assert
      expect(act).toThrow(BumpError);
      expect(act).toThrow(/2 times/);
    });

    it('should refuse a version that would deform the host document', () => {
      // Arrange
      const content = '{\n  "version": "1.0.0"\n}\n';

      // Act
      const act = () => apply('node-version', 'package.json', content, 'not a version');

      // Assert
      expect(act).toThrow(BumpError);
      expect(act).toThrow(/not a usable version/);
    });

    it('should strip a single leading v, matching the scripts it replaces', () => {
      // Arrange
      const inputs = ['v1.2.3', 'valpha', '1.2.3'];

      // Act
      const actual = inputs.map(normalizeVersion);

      // Assert
      expect(actual).toEqual(['1.2.3', 'valpha', '1.2.3']);
    });

    it('should report the previous value and leave every other byte untouched', () => {
      // Arrange
      const content = '{\n  "name": "thing",\n  "version": "1.0.0",\n  "private": true\n}\n';

      // Act
      const outcome = bumpPreset('node-version').apply('package.json', content, '2.0.0');

      // Assert
      expect(outcome.from).toBe('1.0.0');
      expect(outcome.content).toBe('{\n  "name": "thing",\n  "version": "2.0.0",\n  "private": true\n}\n');
    });
  });

  describe('node-version', () => {
    it('should bump the top-level version and ignore a nested one', () => {
      // Arrange
      const content =
        '{\n  "version": "1.0.0",\n  "dependencies": {\n    "dep": {\n      "version": "9.9.9"\n    }\n  }\n}\n';

      // Act
      const actual = apply('node-version', 'package.json', content);

      // Assert
      expect(actual).toContain('"version": "2.0.0"');
      expect(actual).toContain('"version": "9.9.9"');
    });
  });

  describe('dart-version', () => {
    it('should bump a top-level pubspec version', () => {
      // Arrange
      const content = 'name: thing\nversion: 1.0.0\nhomepage: x\n';

      // Act
      const actual = apply('dart-version', 'pubspec.yaml', content);

      // Assert
      expect(actual).toBe('name: thing\nversion: 2.0.0\nhomepage: x\n');
    });

    it('should bump a quoted pubspec version', () => {
      // Arrange
      const content = "name: thing\nversion: '1.0.0'\n";

      // Act
      const actual = apply('dart-version', 'pubspec.yaml', content);

      // Assert
      expect(actual).toBe("name: thing\nversion: '2.0.0'\n");
    });
  });

  describe('dotnet-version', () => {
    it('should bump a single Version property', () => {
      // Arrange
      const content = '<Project>\n  <Version>1.0.0</Version>\n</Project>\n';

      // Act
      const actual = apply('dotnet-version', 'Version.props', content);

      // Assert
      expect(actual).toBe('<Project>\n  <Version>2.0.0</Version>\n</Project>\n');
    });
  });

  describe('plain-version — the fourth preset', () => {
    it('should replace the whole version line and preserve the trailing newline', () => {
      // Arrange
      const content = '1.0.0\n';

      // Act
      const outcome = bumpPreset('plain-version').apply('VERSION', content, 'v2.0.0');

      // Assert
      expect(outcome.from).toBe('1.0.0');
      expect(outcome.content).toBe('2.0.0\n');
    });

    it('should preserve a file with no trailing newline', () => {
      // Arrange
      const content = '1.0.0';

      // Act
      const actual = apply('plain-version', 'VERSION', content);

      // Assert
      expect(actual).toBe('2.0.0');
    });

    it('should treat a blank file as ABSENT rather than write a version into it', () => {
      // Arrange
      const content = '\n \n';

      // Act
      const act = () => apply('plain-version', 'VERSION', content);

      // Assert
      expect(act).toThrow(BumpError);
      expect(act).toThrow(/declares no/);
    });

    it('should treat a multi-line file as AMBIGUOUS rather than pick a line', () => {
      // Arrange
      const content = '1.0.0\nsomething-else\n';

      // Act
      const act = () => apply('plain-version', 'VERSION', content);

      // Assert
      expect(act).toThrow(BumpError);
      expect(act).toThrow(/2 times/);
    });
  });

  describe('path resolution', () => {
    it('should use the built-in default when no file is named', () => {
      // Arrange
      const file = null;

      // Act
      const node = bumpPath('node-version', file);
      const plain = bumpPath('plain-version', file);

      // Assert
      expect(node).toBe('package.json');
      expect(plain).toBe('VERSION');
    });

    it('should prefer an override, which is the NON-ROOT case dart-lib needs', () => {
      // Arrange
      const file = 'packages/diene_dart_lib/pubspec.yaml';

      // Act
      const actual = bumpPath('dart-version', file);

      // Assert
      expect(actual).toBe('packages/diene_dart_lib/pubspec.yaml');
    });

    it('should REFUSE dotnet-version with no file, because no default can be correct', () => {
      // Arrange
      const file = null;

      // Act
      const act = () => bumpPath('dotnet-version', file);

      // Assert
      expect(act).toThrow(BumpError);
      expect(act).toThrow(/must name one explicitly/);
    });

    it('should reject an unknown bump type', () => {
      // Arrange
      const type = 'nope' as 'node-version';

      // Act
      const act = () => bumpPreset(type);

      // Assert
      expect(act).toThrow(BumpError);
    });
  });

  it('should expose exactly the four shipped preset names', () => {
    // Arrange
    const expected = ['dart-version', 'dotnet-version', 'node-version', 'plain-version'] as const;

    // Act
    const actual = [...bumpPresetNames()].sort();

    // Assert
    expect(actual).toEqual([...expected]);
  });
});
