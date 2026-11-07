import { describe, expect, it } from 'bun:test';
import { renderRefusal, TagGuard } from '../../../src/lib/release/tag-guard';
import { FakeTagReader } from '../../helpers/fakes';

function guard(all: string[], visible: string[] = [], mutate: (reader: FakeTagReader) => void = () => {}): TagGuard {
  const reader = new FakeTagReader();
  reader.all = all;
  reader.visible = visible;
  mutate(reader);
  return new TagGuard(reader);
}

async function highestUnreachable(all: string[]): Promise<string> {
  const refusal = await guard(all).checkVisibility();
  return refusal?.message ?? 'NO REFUSAL';
}

describe('tag guard', () => {
  describe('checkVersion', () => {
    it('should refuse a version whose tag already exists, prefixed or bare', async () => {
      // Arrange
      const prefixedGuard = guard(['v1.0.1']);
      const bareGuard = guard(['1.0.1']);

      // Act
      const prefixed = await prefixedGuard.checkVersion('1.0.1', 'v1.0.1');
      const bare = await bareGuard.checkVersion('v1.0.1', 'v1.0.1');

      // Assert
      for (const refusal of [prefixed, bare]) {
        expect(refusal?.code).toBe('tag-collision');
        expect(refusal?.message).toContain('already taken');
      }
    });

    it('should refuse regardless of who minted the tag, because it cannot know', async () => {
      // Arrange
      const reader = new FakeTagReader();
      reader.all = ['v1.0.1'];

      // Act
      const identityKeys = Object.keys(reader).filter(key => /tagger|committer|author|date|message/i.test(key));
      const actual = await new TagGuard(reader).checkVersion('1.0.1', 'v1.0.1');

      // Assert
      expect(identityKeys).toEqual([]);
      expect(actual).not.toBeNull();
    });

    it('should allow a free version — the must-differ control', async () => {
      // Arrange
      const subject = guard(['v1.0.0', 'v1.0.1']);

      // Act
      const actual = await subject.checkVersion('1.0.2', 'v1.0.2');

      // Assert
      expect(actual).toBeNull();
    });

    it('should refuse a collision on a NON-DEFAULT tag format', async () => {
      // Arrange
      const taken = guard(['release-1.0.0']);
      const untaken = guard(['release-0.9.0']);

      // Act
      const custom = await taken.checkVersion('1.0.0', 'release-1.0.0');
      const free = await untaken.checkVersion('1.0.0', 'release-1.0.0');

      // Assert
      expect(custom?.code).toBe('tag-collision');
      expect(custom?.message).toContain('release-1.0.0');
      expect(free).toBeNull();
    });

    it('should refuse an unparseable version rather than guess what to check', async () => {
      // Arrange
      const subject = guard([]);

      // Act
      const actual = await subject.checkVersion('not-a-version', 'not-a-version');

      // Assert
      expect(actual?.code).toBe('invalid-version');
    });

    it('should refuse a MALFORMED version rather than accept it as a release', async () => {
      // Arrange
      const malformed = ['1.2.3-', '1.2.3+', '01.2.3', '1.2.3-rc..1', '1.02.3'];

      // Act
      const actual = await Promise.all(malformed.map(version => guard([]).checkVersion(version, version)));

      // Assert
      expect(actual.map(refusal => refusal?.code)).toEqual(malformed.map(() => 'invalid-version'));
    });

    it('should still accept every well-formed version — the must-differ control', async () => {
      // Arrange
      const wellFormed = ['1.2.3', 'v1.2.3', 'v1.2.3-rc.1', '1.2.3+build.4', '1.0.0+build-4', '0.0.0'];

      // Act
      const actual = await Promise.all(wellFormed.map(version => guard([]).checkVersion(version, version)));

      // Assert
      expect(actual).toEqual(wellFormed.map(() => null));
    });
  });

  describe('checkVisibility', () => {
    it('should refuse when a version tag exists that HEAD cannot reach', async () => {
      // Arrange
      const subject = guard(['v1.0.0', 'v1.0.1'], []);

      // Act
      const actual = await subject.checkVisibility();

      // Assert
      expect(actual?.code).toBe('tag-not-visible');
      expect(actual?.message).toContain('v1.0.1');
      expect(actual?.message).toContain('committed release with no tag');
    });

    it('should pass when every version tag is reachable — the must-differ control', async () => {
      // Arrange
      const subject = guard(['v1.0.0', 'v1.0.1'], ['v1.0.0', 'v1.0.1']);

      // Act
      const actual = await subject.checkVisibility();

      // Assert
      expect(actual).toBeNull();
    });

    it('should ignore floating major and minor tags that move by design', async () => {
      // Arrange
      const subject = guard(['v3', 'v3.1'], []);

      // Act
      const actual = await subject.checkVisibility();

      // Assert
      expect(actual).toBeNull();
    });

    it('should not count a MALFORMED tag as a blocking version tag', async () => {
      // Arrange
      const subject = guard(['1.2.3-', '1.2.3+', '01.2.3'], []);

      // Act
      const actual = await subject.checkVisibility();

      // Assert
      expect(actual).toBeNull();
    });

    it('should still count a well-formed unreachable tag beside malformed ones', async () => {
      // Arrange
      const subject = guard(['1.2.3-', '01.2.3', 'v2.0.0'], []);

      // Act
      const actual = await subject.checkVisibility();

      // Assert
      expect(actual?.code).toBe('tag-not-visible');
      expect(actual?.message).toContain('highest: v2.0.0');
      expect(actual?.message).toContain('1 version tag(s)');
    });

    it('should name the highest unreachable tag across every ordering rule', async () => {
      // Arrange
      const cases: Array<[string[], string]> = [
        [['1.0.0', '2.0.0'], 'highest: 2.0.0'],
        [['1.1.0', '1.0.0'], 'highest: 1.1.0'],
        [['1.0.1', '1.0.0'], 'highest: 1.0.1'],
        [['1.0.0', '1.0.0-rc.1'], 'highest: 1.0.0'],
        [['1.0.0-rc.1', '1.0.0'], 'highest: 1.0.0'],
        [['1.0.0-rc.1', '1.0.0-rc.2'], 'highest: 1.0.0-rc.2'],
        [['1.0.0-rc.1', 'v1.0.0-rc.1'], 'highest: 1.0.0-rc.1'],
      ];

      // Act
      const actual = await Promise.all(cases.map(([tags]) => highestUnreachable(tags)));

      // Assert
      cases.forEach(([, expected], index) => {
        expect(actual[index]).toContain(expected);
      });
    });

    it('should not read a dash inside build metadata as a prerelease', async () => {
      // Arrange
      const tags = ['1.0.0-rc.1', '1.0.0+build-4'];

      // Act
      const actual = await highestUnreachable(tags);

      // Assert
      expect(actual).toContain('highest: 1.0.0+build-4');
    });
  });

  describe('preflight', () => {
    it('should REFUSE a shallow clone rather than report a clear result', async () => {
      // Arrange
      const subject = guard([], [], reader => {
        reader.shallow = true;
      });

      // Act
      const actual = await subject.checkVisibility();

      // Assert
      expect(actual?.code).toBe('shallow-clone');
      expect(actual?.message).toContain('cannot be ruled out');
    });

    it('should REFUSE when the repository cannot be inspected at all', async () => {
      // Arrange
      const failing = () =>
        guard([], [], reader => {
          reader.failure = new Error('not a git repository');
        });

      // Act
      const visibility = await failing().checkVisibility();
      const version = await failing().checkVersion('1.0.0', 'v1.0.0');

      // Assert
      expect(visibility?.code).toBe('not-a-git-repo');
      expect(version?.code).toBe('not-a-git-repo');
      expect(visibility?.message).toContain('not a git repository');
    });

    it('should carry a non-Error failure through as text', async () => {
      // Arrange
      const subject = guard([], [], reader => {
        reader.failure = 'permission denied' as unknown as Error;
      });

      // Act
      const actual = await subject.checkVisibility();

      // Assert
      expect(actual?.code).toBe('not-a-git-repo');
      expect(actual?.message).toContain('permission denied');
    });
  });

  it('should render a refusal as code-then-message so CI can grep the code', async () => {
    // Arrange
    const refusal = await guard(['v1.0.1']).checkVersion('1.0.1', 'v1.0.1');
    if (refusal === null) throw new Error('expected a refusal');

    // Act
    const actual = renderRefusal(refusal);

    // Assert
    expect(actual).toStartWith('tag-collision: ');
  });
});
