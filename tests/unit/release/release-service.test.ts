import { describe, expect, it } from 'bun:test';
import type { ReleaserConfig } from '../../../src/lib/config/model';
import { ConfigError, ReleaseError } from '../../../src/lib/errors';
import { ConventionsService } from '../../../src/lib/release/conventions-service';
import { HookTemplate } from '../../../src/lib/release/hook-template';
import { NotesService } from '../../../src/lib/release/notes-service';
import { describeConventionsCheck, ReleaseService, userMessage } from '../../../src/lib/release/release-service';
import { TagGuard } from '../../../src/lib/release/tag-guard';
import { VersionService } from '../../../src/lib/release/version-service';
import {
  FakeClock,
  FakeConfigRepository,
  FakeGit,
  FakeGitHub,
  FakeHookRunner,
  FakeTagReader,
  loadedConfig,
  MemoryFileSystem,
  TEST_CONFIG,
} from '../../helpers/fakes';

async function rejectionOf(work: Promise<unknown>): Promise<Error> {
  return work.then(
    () => {
      throw new Error('expected the operation to reject');
    },
    (error: unknown) => error as Error,
  );
}

function fixture(config = TEST_CONFIG): {
  readonly subject: ReleaseService;
  readonly files: MemoryFileSystem;
  readonly git: FakeGit;
  readonly hooks: FakeHookRunner;
  readonly github: FakeGitHub;
  readonly tags: FakeTagReader;
} {
  const files = new MemoryFileSystem({ 'Changelog.md': '# Changelog\n', 'bun.lock': 'locked' });
  const git = new FakeGit();
  git.commits = [{ sha: 'a'.repeat(40), message: 'feat: add release' }];
  const hooks = new FakeHookRunner();
  const github = new FakeGitHub();
  const tags = new FakeTagReader();
  return {
    files,
    git,
    hooks,
    github,
    tags,
    subject: new ReleaseService(
      new FakeConfigRepository(loadedConfig(config)),
      files,
      git,
      hooks,
      github,
      new VersionService(),
      new NotesService(),
      new ConventionsService(),
      new HookTemplate(),
      new FakeClock(),
      new TagGuard(tags),
    ),
  };
}

describe('release service', () => {
  it('should keep dry-run pure', async () => {
    // Arrange
    const { subject, files, git } = fixture();
    const before = new Map(files.values);

    // Act
    const actual = await subject.release('release.yaml', true);

    // Assert
    expect(actual?.version).toBe('1.0.0');
    expect(files.values).toEqual(before);
    expect(git.calls).toEqual([]);
  });

  it('should execute writes, exact commit, tag, and atomic-push seam in order', async () => {
    // Arrange
    const config = {
      ...TEST_CONFIG,
      release: {
        ...TEST_CONFIG.release,
        hooks: {
          prepare: [
            { phase: 'beforeWrite' as const, command: './before ${version}' },
            { phase: 'afterWrite' as const, command: './after ${version}' },
          ],
          success: ['./success ${version}'],
        },
      },
    };
    const { subject, files, git, hooks } = fixture(config);

    // Act
    const actual = await subject.release();

    // Assert
    expect(actual?.version).toBe('1.0.0');
    expect(files.values.get('Changelog.md')).toContain('## 1.0.0');
    expect(files.values.get('docs/developer/CommitConventions.md')).toContain('## Types');
    expect(git.calls).toEqual([
      'stage:Changelog.md,docs/developer/CommitConventions.md',
      'commit',
      'tag:v1.0.0',
      'push:main:v1.0.0',
    ]);
    expect(git.committedMessage).toStartWith('release: 1.0.0\n\n## 1.0.0');
    expect(git.committedMessage).not.toMatch(/\[(skip ci|ci skip)\]/i);
    expect(hooks.commands).toEqual(["./before '1.0.0'", "./after '1.0.0'", "./success '1.0.0'"]);
  });

  it('should fail before staging when a hook changes an unexpected asset or lockfile', async () => {
    // Arrange
    const unexpected = fixture();
    unexpected.git.changed = ['unexpected.txt'];
    const lock = fixture({
      ...TEST_CONFIG,
      release: {
        ...TEST_CONFIG.release,
        hooks: { prepare: [{ phase: 'beforeWrite', command: './change-lock' }], success: [] },
      },
    });
    const renamed = fixture({
      ...TEST_CONFIG,
      release: {
        ...TEST_CONFIG.release,
        commit: {
          ...TEST_CONFIG.release.commit,
          assets: [...TEST_CONFIG.release.commit.assets, 'allowed.txt'],
        },
      },
    });
    renamed.git.changed = ['allowed.txt', 'outside.txt'];
    lock.hooks.run = async command => {
      lock.hooks.commands.push(command);
      lock.files.values.set('bun.lock', 'changed');
    };

    // Act
    const unexpectedFailure = await rejectionOf(unexpected.subject.release());
    const lockFailure = await rejectionOf(lock.subject.release());
    const renamedFailure = await rejectionOf(renamed.subject.release());

    // Assert
    expect(unexpectedFailure.message).toContain('outside configured assets');
    expect(lockFailure.message).toContain('lockfile changed unexpectedly');
    expect(renamedFailure.message).toContain('outside.txt');
    expect(unexpected.git.calls).toEqual([]);
    expect(lock.git.calls).toEqual([]);
    expect(renamed.git.calls).toEqual([]);
  });

  it('should stop before tag and push when the release commit leaves a dirty path', async () => {
    // Arrange
    const dirty = fixture();
    let cleanChecks = 0;
    dirty.git.isClean = async () => {
      cleanChecks += 1;
      return cleanChecks === 1;
    };

    // Act
    const failure = await rejectionOf(dirty.subject.release());

    // Assert
    expect(failure.message).toContain('dirty after the release commit');
    expect(dirty.git.calls).toEqual(['stage:Changelog.md,docs/developer/CommitConventions.md', 'commit']);
    expect(dirty.git.calls.some(call => call.startsWith('tag:') || call.startsWith('push:'))).toBe(false);
  });

  it('should reject an ambiguous hook template before invoking the hook runner', async () => {
    // Arrange
    const invalid = fixture({
      ...TEST_CONFIG,
      release: {
        ...TEST_CONFIG.release,
        hooks: {
          prepare: [{ phase: 'beforeWrite', command: "hook '${version}" }],
          success: [],
        },
      },
    });

    // Act
    const failure = await rejectionOf(invalid.subject.release());

    // Assert
    expect(failure.message).toContain('unterminated');
    expect(invalid.hooks.commands).toEqual([]);
    expect(invalid.git.calls).toEqual([]);
  });

  it('should validate the rendered tag before any mutation', async () => {
    // Arrange
    const invalid = fixture({
      ...TEST_CONFIG,
      release: { ...TEST_CONFIG.release, tagFormat: 'bad..${version}' },
    });
    invalid.git.tagValidationError = new Error('invalid tag ref');
    const before = new Map(invalid.files.values);

    // Act
    const previewFailure = await rejectionOf(invalid.subject.preview());
    const dryRunFailure = await rejectionOf(invalid.subject.release('release.yaml', true));
    const releaseFailure = await rejectionOf(invalid.subject.release());

    // Assert
    expect(previewFailure.message).toContain('invalid tag ref');
    expect(dryRunFailure.message).toContain('invalid tag ref');
    expect(releaseFailure.message).toContain('invalid tag ref');
    expect(invalid.files.values).toEqual(before);
    expect(invalid.hooks.commands).toEqual([]);
    expect(invalid.git.calls).toEqual([]);
    expect(invalid.git.validatedTags).toEqual(['bad..1.0.0', 'bad..1.0.0', 'bad..1.0.0']);
  });

  it('should prepend notes at byte zero when the changelog has no preamble', async () => {
    // Arrange
    const release = fixture();
    release.files.values.set('Changelog.md', '## 0.9.0 (2026-01-01)\n\nold release\n');

    // Act
    await release.subject.release();
    const changelog = release.files.values.get('Changelog.md');

    // Assert
    expect(changelog).toStartWith('## 1.0.0');
    expect(changelog).toContain('## 0.9.0 (2026-01-01)\n\nold release\n');
  });

  it('should publish the configured GitHub release payload and reject a non-GitHub origin', async () => {
    // Arrange
    const config: ReleaserConfig = {
      ...TEST_CONFIG,
      release: {
        ...TEST_CONFIG.release,
        github: {
          enabled: true,
          successComment: 'Released ${version}: ${notes}',
          releasedLabels: ['released', 'shipped'],
        },
      },
    };
    const published = fixture(config);
    const missingRepository = fixture(config);
    missingRepository.git.githubSlug = null;

    // Act
    await published.subject.release();
    const missingFailure = await rejectionOf(missingRepository.subject.release());

    // Assert
    expect(published.github.requests).toHaveLength(1);
    expect(published.github.requests[0]).toMatchObject({
      repository: 'AtomiCloud/example',
      tag: 'v1.0.0',
      version: '1.0.0',
      releasedLabels: ['released', 'shipped'],
    });
    expect(published.github.requests[0]?.successComment).toStartWith('Released 1.0.0: ## 1.0.0');
    expect(missingFailure.message).toContain('origin is not a GitHub repository');
    expect(missingRepository.github.requests).toEqual([]);
  });

  it('should expose no-release, precondition, empty-asset, and hook failure contracts', async () => {
    // Arrange
    const noRelease = fixture();
    noRelease.git.commits = [{ sha: 'a', message: 'docs: update guide' }];
    const dirty = fixture();
    dirty.git.clean = false;
    const empty = fixture();
    empty.git.changed = [];
    const failingHook = fixture({
      ...TEST_CONFIG,
      release: {
        ...TEST_CONFIG.release,
        hooks: { prepare: [{ phase: 'beforeWrite', command: './fail' }], success: [] },
      },
    });
    failingHook.hooks.failure = new Error('hook exploded');

    // Act
    const preview = await noRelease.subject.preview();
    const released = await noRelease.subject.release();
    const dirtyFailure = await rejectionOf(dirty.subject.release());
    const emptyFailure = await rejectionOf(empty.subject.release());
    const hookFailure = await rejectionOf(failingHook.subject.release());

    // Assert
    expect(preview).toBeNull();
    expect(released).toBeNull();
    expect(dirtyFailure.message).toContain('working tree must be clean');
    expect(emptyFailure.message).toContain('no configured asset changes');
    expect(hookFailure.message).toContain('prepare:beforeWrite failed: hook exploded');
  });

  it('should write conventions independently and render safe user-facing errors', async () => {
    // Arrange
    const release = fixture();

    // Act
    const loaded = await release.subject.writeConventions('custom.yaml');
    const messages = [
      userMessage(new ReleaseError('release failed', 'test')),
      userMessage(new Error('ordinary failure')),
      userMessage({ reason: 'unknown' }),
    ];

    // Assert
    expect(loaded.config).toBe(TEST_CONFIG);
    expect(release.files.values.get(TEST_CONFIG.conventions.path)).toContain('## Types');
    expect(messages).toEqual(['release failed', 'ordinary failure', '[object Object]']);
  });
});

describe('conventions check (D9)', () => {
  const DOC = TEST_CONFIG.conventions.path;

  async function generated(): Promise<{ release: ReturnType<typeof fixture>; body: string }> {
    const release = fixture();
    await release.subject.writeConventions();
    const body = release.files.values.get(DOC);
    if (body === undefined) throw new Error('fixture did not generate a document');
    return { release, body };
  }

  it('A1: should report a match on the bytes the generator itself wrote', async () => {
    // Arrange
    const { release } = await generated();

    // Act
    const actual = await release.subject.checkConventions();

    // Assert
    expect(actual.status).toBe('match');
    expect(actual.diff).toBe('');
    expect(actual.path).toBe(DOC);
  });

  it('A2: should report drift when the document body is edited', async () => {
    // Arrange
    const { release, body } = await generated();
    release.files.values.set(DOC, body.replace('## Types', '## Types (hand-edited)'));

    // Act
    const actual = await release.subject.checkConventions();

    // Assert
    expect(actual.status).toBe('drift');
    expect(actual.diff).toContain('## Types (hand-edited)');
  });

  it('A3: should report drift on a single appended whitespace byte', async () => {
    // Arrange
    const { release, body } = await generated();
    release.files.values.set(DOC, `${body} `);

    // Act
    const actual = await release.subject.checkConventions();

    // Assert
    expect(actual.status).toBe('drift');
    expect(actual.diff).not.toBe('');
  });

  it('A4: should report a missing document rather than a match', async () => {
    // Arrange
    const release = fixture();

    // Act
    const actual = await release.subject.checkConventions();

    // Assert
    expect(actual.status).toBe('missing');
    expect(actual.actual).toBeNull();
    expect(actual.diff).toBe('');
  });

  it('A5: should report drift when the configuration moves and the document does not', async () => {
    // Arrange
    const { body } = await generated();
    const moved = fixture({
      ...TEST_CONFIG,
      types: [
        ...TEST_CONFIG.types,
        { type: 'perf', desc: 'Performance', scopes: { default: { desc: 'Perf', release: 'patch' } } },
      ],
    });
    moved.files.values.set(DOC, body);

    // Act
    const actual = await moved.subject.checkConventions();

    // Assert
    expect(actual.status).toBe('drift');
    expect(actual.diff).toContain('perf');
  });

  it('A6: should stay green after a byte-identical rewrite', async () => {
    // Arrange
    const { release } = await generated();
    await release.subject.writeConventions();

    // Act
    const actual = await release.subject.checkConventions();

    // Assert
    expect(actual.status).toBe('match');
  });

  it('A7: should not modify the document it judges', async () => {
    // Arrange
    const { release, body } = await generated();
    const drifted = `${body}trailing junk\n`;
    release.files.values.set(DOC, drifted);

    // Act
    const actual = await release.subject.checkConventions();

    // Assert
    expect(actual.status).toBe('drift');
    expect(release.files.values.get(DOC)).toBe(drifted);
  });

  it('A8: should surface an unreadable configuration as a failure, not a match', async () => {
    // Arrange
    const release = fixture();
    const broken = new ReleaseService(
      {
        load: async () => {
          throw new ConfigError('failed to read YAML configuration "nope.yaml": file not found: nope.yaml');
        },
        writeCanonical: async () => undefined,
      },
      release.files,
      release.git,
      release.hooks,
      release.github,
      new VersionService(),
      new NotesService(),
      new ConventionsService(),
      new HookTemplate(),
      new FakeClock(),
      new TagGuard(release.tags),
    );

    // Act
    const act = broken.checkConventions('nope.yaml');

    // Assert
    await expect(act).rejects.toThrow('failed to read YAML configuration');
  });

  it('should name the rule and the remedy in every verdict', async () => {
    // Arrange
    const { release, body } = await generated();

    // Act
    const match = describeConventionsCheck(await release.subject.checkConventions());
    const missingCheck = await fixture().subject.checkConventions();
    release.files.values.set(DOC, `${body}drift\n`);
    const drift = describeConventionsCheck(await release.subject.checkConventions());

    // Assert
    expect(match).toContain('is up to date with');
    expect(describeConventionsCheck(missingCheck)).toContain('regenerate-only');
    expect(describeConventionsCheck(missingCheck)).toContain('`releaser conventions`');
    expect(drift).toContain('D9');
    expect(drift).toContain('Hand-edits are not permitted');
    expect(drift).toContain('+drift');
  });

  it('should point the remedy at a non-default configuration path', async () => {
    // Arrange
    const release = fixture();

    // Act
    const actual = describeConventionsCheck(await release.subject.checkConventions('custom.yaml'));

    // Assert
    expect(actual).toContain("`releaser conventions -c 'custom.yaml'`");
  });

  it('should quote a configuration path containing whitespace in the remedy', async () => {
    // Arrange
    const release = fixture();

    // Act
    const spaced = describeConventionsCheck(await release.subject.checkConventions('my configs/rel.yaml'));
    const quoted = describeConventionsCheck(await release.subject.checkConventions("odd'name.yaml"));

    // Assert
    expect(spaced).toContain("`releaser conventions -c 'my configs/rel.yaml'`");
    expect(quoted).toContain("odd'\\''name.yaml");
  });
});

describe('version bumps (write:versions)', () => {
  function bumpFixture(bumps: ReleaserConfig['release']['bumps'], seed: Record<string, string>) {
    const config = {
      ...TEST_CONFIG,
      release: { ...TEST_CONFIG.release, bumps, commit: { ...TEST_CONFIG.release.commit, assets: ['**'] } },
    };
    const harness = fixture(config);
    for (const [path, content] of Object.entries(seed)) harness.files.values.set(path, content);
    harness.git.changed = Object.keys(seed);
    return harness;
  }

  it('should bump a plain-text VERSION during the release, not merely on disk beforehand', async () => {
    // Arrange
    const { subject, files } = bumpFixture([{ type: 'plain-version', file: null, reason: null }], {
      VERSION: '0.1.0\n',
    });

    // Act
    await subject.release();

    // Assert
    expect(await files.readText('VERSION')).toBe('1.0.0\n');
  });

  it('should bump a NON-ROOT overridden path — the shape dart-lib actually needs', async () => {
    // Arrange
    const { subject, files } = bumpFixture(
      [{ type: 'dart-version', file: 'packages/diene_dart_lib/pubspec.yaml', reason: 'monorepo package layout' }],
      { 'packages/diene_dart_lib/pubspec.yaml': 'name: diene\nversion: 0.1.0\n' },
    );

    // Act
    await subject.release();

    // Assert
    expect(await files.readText('packages/diene_dart_lib/pubspec.yaml')).toBe('name: diene\nversion: 1.0.0\n');
  });

  it('should bump several files in one release', async () => {
    // Arrange
    const { subject, files } = bumpFixture(
      [
        { type: 'plain-version', file: null, reason: null },
        { type: 'node-version', file: null, reason: null },
      ],
      { VERSION: '0.1.0\n', 'package.json': '{\n  "version": "0.1.0"\n}\n' },
    );

    // Act
    await subject.release();

    // Assert
    expect(await files.readText('VERSION')).toBe('1.0.0\n');
    expect(await files.readText('package.json')).toBe('{\n  "version": "1.0.0"\n}\n');
  });

  it('should REFUSE when a bump target does not exist rather than create it', async () => {
    // Arrange
    const { subject } = bumpFixture([{ type: 'plain-version', file: null, reason: null }], {});

    // Act
    const act = subject.release();

    // Assert
    await expect(act).rejects.toThrow(/bump target VERSION does not exist/);
  });

  it('should write NOTHING when any one bump fails — all or nothing', async () => {
    // Arrange
    const { subject, files } = bumpFixture(
      [
        { type: 'plain-version', file: null, reason: null },
        { type: 'node-version', file: null, reason: null },
      ],
      { VERSION: '0.1.0\n', 'package.json': '{\n  "name": "thing"\n}\n' },
    );

    // Act
    const failure = await rejectionOf(subject.release());

    // Assert
    expect(failure.message).toMatch(/declares no/);
    expect(await files.readText('VERSION')).toBe('0.1.0\n');
  });
});

describe('standalone bump', () => {
  function standaloneFixture(bumps: ReleaserConfig['release']['bumps'], seed: Record<string, string>) {
    const harness = fixture({ ...TEST_CONFIG, release: { ...TEST_CONFIG.release, bumps } });
    for (const [path, content] of Object.entries(seed)) harness.files.values.set(path, content);
    return harness;
  }

  it('should stamp the configured files and report which it wrote', async () => {
    // Arrange
    const { subject, files } = standaloneFixture(
      [
        { type: 'plain-version', file: null, reason: null },
        { type: 'node-version', file: null, reason: null },
      ],
      { VERSION: '0.1.0\n', 'package.json': '{\n  "version": "0.1.0"\n}\n' },
    );

    // Act
    const written = await subject.bump('v2.5.0');

    // Assert
    expect([...written]).toEqual(['VERSION', 'package.json']);
    expect(await files.readText('VERSION')).toBe('2.5.0\n');
    expect(await files.readText('package.json')).toBe('{\n  "version": "2.5.0"\n}\n');
  });

  it('should write nothing and report nothing when no bumps are configured', async () => {
    // Arrange
    const { subject, files } = standaloneFixture([], { VERSION: '0.1.0\n' });

    // Act
    const written = await subject.bump('2.5.0');

    // Assert
    expect([...written]).toEqual([]);
    expect(await files.readText('VERSION')).toBe('0.1.0\n');
  });

  it('should refuse a missing target rather than create it', async () => {
    // Arrange
    const { subject } = standaloneFixture([{ type: 'plain-version', file: null, reason: null }], {});

    // Act
    const act = subject.bump('2.5.0');

    // Assert
    await expect(act).rejects.toThrow(/bump target VERSION does not exist/);
  });
});
