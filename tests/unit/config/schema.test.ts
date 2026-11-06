import { describe, expect, it } from 'bun:test';
import { detectSchemaVersion, parseCanonicalV2 } from '../../../src/lib/config/schema';
import { ConfigError } from '../../../src/lib/errors';

function minimal(): Record<string, unknown> {
  return {
    schemaVersion: 2,
    types: [{ type: 'feat', desc: 'Features', scopes: { default: { desc: 'Feature', release: 'minor' } } }],
    conventions: { path: 'CommitConventions.md', template: 'CONVENTION_DOCS_PLACEHOLDER' },
    release: {
      branches: ['main'],
      changelog: { path: 'Changelog.md' },
      commit: { message: 'release: ${version}\n\n${notes}', assets: ['Changelog.md'] },
    },
  };
}

function withBumps(bumps: readonly Record<string, unknown>[]): Record<string, unknown> {
  const input = minimal();
  (input.release as Record<string, unknown>).bumps = bumps;
  return input;
}

describe('canonical v2 schema', () => {
  it('should apply nested defaults', () => {
    // Arrange
    const input = minimal();

    // Act
    const actual = parseCanonicalV2(input);

    // Assert
    expect(actual.lint.header.maxLength).toBe(72);
    expect(actual.lint.body.maxLineLength).toBe(80);
    expect(actual.release.tagFormat).toBe('v${version}');
    expect(actual.release.github).toBe(false);
  });

  it('should reject unknown nested keys with a dotted path', () => {
    // Arrange
    const input = minimal();
    (input.release as Record<string, unknown>).channel = 'next';

    // Act
    const act = () => parseCanonicalV2(input);

    // Assert
    expect(act).toThrow(ConfigError);
    expect(act).toThrow('release: Unrecognized key');
  });

  it('should reject duplicate types and skip-CI release messages', () => {
    // Arrange
    const duplicate = minimal();
    duplicate.types = [...(duplicate.types as unknown[]), ...(duplicate.types as unknown[])];
    const skip = minimal();
    ((skip.release as Record<string, unknown>).commit as Record<string, unknown>).message =
      'release: ${version} [skip ci]';

    // Act
    const parseDuplicate = () => parseCanonicalV2(duplicate);
    const parseSkip = () => parseCanonicalV2(skip);

    // Assert
    expect(parseDuplicate).toThrow('type names must be unique');
    expect(parseSkip).toThrow('skip-CI');
  });

  it('should reject prerelease branch objects and invalid tag formats', () => {
    // Arrange
    const branch = minimal();
    (branch.release as Record<string, unknown>).branches = [{ name: 'main', prerelease: true }];
    const tag = minimal();
    (tag.release as Record<string, unknown>).tagFormat = 'release';

    // Act
    const parseBranch = () => parseCanonicalV2(branch);
    const parseTag = () => parseCanonicalV2(tag);

    // Assert
    expect(parseBranch).toThrow(ConfigError);
    expect(parseTag).toThrow('exactly one ${version}');
  });

  it('should reject duplicate branches, assets, and keywords together', () => {
    // Arrange
    const input = minimal();
    input.keywords = ['BREAKING CHANGE', 'BREAKING CHANGE'];
    const release = input.release as Record<string, unknown>;
    release.branches = ['main', 'main'];
    const commit = release.commit as Record<string, unknown>;
    commit.assets = ['Changelog.md', 'Changelog.md'];

    // Act
    const act = () => parseCanonicalV2(input);

    // Assert
    expect(act).toThrow('branches must be unique');
    expect(act).toThrow('assets must be unique');
    expect(act).toThrow('keywords must be unique');
  });

  it('should accept preset-default and overridden bump entries with null defaults', () => {
    // Arrange
    const input = withBumps([
      { type: 'node-version' },
      { type: 'dotnet-version', file: 'src/App.csproj', reason: 'the project file lives under src' },
    ]);

    // Act
    const actual = parseCanonicalV2(input);

    // Assert
    expect(actual.release.bumps).toEqual([
      { type: 'node-version', file: null, reason: null },
      { type: 'dotnet-version', file: 'src/App.csproj', reason: 'the project file lives under src' },
    ]);
  });

  it('should reject a bump entry that overrides its file without a reason', () => {
    // Arrange
    const input = withBumps([{ type: 'node-version', file: 'packages/app/package.json' }]);

    // Act
    const act = () => parseCanonicalV2(input);

    // Assert
    expect(act).toThrow(ConfigError);
    expect(act).toThrow('release.bumps.0.reason: a bump entry that names a file must give a non-empty reason');
  });

  it('should reject a dotnet bump entry that names no file', () => {
    // Arrange
    const input = withBumps([{ type: 'dotnet-version', reason: 'no file named' }]);

    // Act
    const act = () => parseCanonicalV2(input);

    // Assert
    expect(act).toThrow(ConfigError);
    expect(act).toThrow('release.bumps.0.file: dotnet-version has no default file');
  });

  it('should detect canonical and legacy documents and explain every invalid root shape', () => {
    // Arrange
    const canonical = minimal();

    // Act
    const detected = [canonical, { branches: ['main'] }, { plugins: [] }].map(detectSchemaVersion);
    const detectNull = () => detectSchemaVersion(null);
    const detectArray = () => detectSchemaVersion([]);
    const detectFuture = () => detectSchemaVersion({ schemaVersion: 3 });
    const detectEmpty = () => detectSchemaVersion({});

    // Assert
    expect(detected).toEqual([2, 1, 1]);
    expect(detectNull).toThrow('configuration must be a mapping');
    expect(detectArray).toThrow('configuration must be a mapping');
    expect(detectFuture).toThrow('unsupported schemaVersion: 3');
    expect(detectEmpty).toThrow('unrecognized configuration');
  });
});
