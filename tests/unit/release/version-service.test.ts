import { describe, expect, it } from 'bun:test';
import type { ReleaserConfig } from '../../../src/lib/config/model';
import { VersionService } from '../../../src/lib/release/version-service';
import { TEST_CONFIG } from '../../helpers/fakes';

describe('version service', () => {
  const subject = new VersionService();

  it('should select the greatest reachable valid stable tag', () => {
    // Arrange
    const tags = ['v1.8.0', 'invalid', 'v2.0.0-alpha.1', 'v1.10.0'];

    // Act
    const actual = subject.latestTag(tags, 'v${version}');

    // Assert
    expect(actual).toEqual({ tag: 'v1.10.0', version: { major: 1, minor: 10, patch: 0 } });
  });

  it.each([
    ['fix: repair', { major: 1, minor: 2, patch: 4 }],
    ['feat: add', { major: 1, minor: 3, patch: 0 }],
    ['feat!: replace', { major: 2, minor: 0, patch: 0 }],
  ])('should apply release precedence for %s', (message, expected) => {
    // Arrange
    const previous = { major: 1, minor: 2, patch: 3 };

    // Act
    const actual = subject.analyze(TEST_CONFIG, previous, [{ sha: 'a', message }]);

    // Assert
    expect(actual?.version).toEqual(expected);
  });

  it('should force the first requested release to 1.0.0', () => {
    // Arrange
    const commits = [{ sha: 'a', message: 'fix: repair' }];

    // Act
    const actual = subject.analyze(TEST_CONFIG, null, commits);

    // Assert
    expect(actual?.version).toEqual({ major: 1, minor: 0, patch: 0 });
  });

  it('should make special scopes override defaults and ignore unknown history', () => {
    // Arrange
    const noRelease = [{ sha: 'a', message: 'feat(no-release): skip' }];
    const unknown = [{ sha: 'a', message: 'unknown!: skip' }];

    // Act
    const noReleaseDecision = subject.analyze(TEST_CONFIG, null, noRelease);
    const unknownDecision = subject.analyze(TEST_CONFIG, null, unknown);

    // Assert
    expect(noReleaseDecision).toBeNull();
    expect(unknownDecision).toBeNull();
  });

  it('should treat a BREAKING CHANGE footer as a major release', () => {
    // Arrange
    const commits = [
      { sha: 'a', message: 'fix: repair a detail\n\nA descriptive body.\n\nBREAKING CHANGE: the contract changed' },
    ];

    // Act
    const actual = subject.analyze(TEST_CONFIG, { major: 1, minor: 2, patch: 3 }, commits);

    // Assert
    expect(actual).toMatchObject({ level: 'major', version: { major: 2, minor: 0, patch: 0 } });
  });

  it('should apply a release-producing special scope across any type, overriding type rules', () => {
    // Arrange
    const config: ReleaserConfig = {
      ...TEST_CONFIG,
      specialScopes: { ...TEST_CONFIG.specialScopes, security: { desc: 'Security fix', release: 'major' } },
    };
    const previous = { major: 1, minor: 2, patch: 3 };

    // Act
    const fix = subject.analyze(config, previous, [{ sha: 'a', message: 'fix(security): patch a hole' }]);
    const docs = subject.analyze(config, previous, [{ sha: 'b', message: 'docs(security): note a hole' }]);

    // Assert
    expect(fix?.level).toBe('major');
    expect(docs?.level).toBe('major');
  });

  it('should compare major, minor, and patch components and reject malformed tag formats', () => {
    // Arrange
    const version = { major: 3, minor: 2, patch: 1 };
    const commits = [
      { sha: 'a', message: 'feat!: replace everything' },
      { sha: 'b', message: 'fix: repair a detail' },
    ];

    // Act
    const latest = subject.latestTag(['v1.9.9', 'v2.0.0', 'v2.0.1'], 'v${version}');
    const zeroPadded = subject.parseTag('v01.2.3', 'v${version}');
    const noPlaceholder = subject.parseTag('v1.2.3', 'release');
    const formatted = subject.format(version);
    const formattedTag = subject.formatTag('release-${version}', version);
    const decision = subject.analyze(TEST_CONFIG, { major: 1, minor: 2, patch: 3 }, commits);

    // Assert
    expect(latest).toEqual({ tag: 'v2.0.1', version: { major: 2, minor: 0, patch: 1 } });
    expect(zeroPadded).toBeNull();
    expect(noPlaceholder).toBeNull();
    expect(formatted).toBe('3.2.1');
    expect(formattedTag).toBe('release-3.2.1');
    expect(decision?.level).toBe('major');
  });
});
