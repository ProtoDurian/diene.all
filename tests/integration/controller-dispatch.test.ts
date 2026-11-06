import { describe, expect, it } from 'bun:test';
import { createProgram, registerDomain } from '../../bin/releaser';
import {
  captureIo,
  FakeClock,
  FakeConfigRepository,
  FakeGit,
  FakeGitHub,
  FakeHookRunner,
  FakeTagReader,
  loadedConfig,
  MemoryFileSystem,
} from '../helpers/fakes';

describe('controller dispatch', () => {
  it.each([
    [['release', '--dry-run']],
    [['lint-commit', 'COMMIT_EDITMSG']],
    [['next']],
    [['changelog']],
    [['bump', '1.2.3']],
    [['conventions']],
    [['migrate']],
  ])('should route %p through its registered action to exactly one exit code', async args => {
    // Arrange
    const io = captureIo();
    const program = createProgram();
    registerDomain(program, {
      io,
      files: new MemoryFileSystem({ COMMIT_EDITMSG: 'feat: add a release capability\n' }),
      configs: new FakeConfigRepository(loadedConfig()),
      git: new FakeGit(),
      hooks: new FakeHookRunner(),
      github: new FakeGitHub(),
      tags: new FakeTagReader(),
      clock: new FakeClock(),
    });

    // Act
    await program.parseAsync(['bun', 'releaser', ...args]);

    // Assert
    expect(io.codes.length).toBe(1);
  });
});
