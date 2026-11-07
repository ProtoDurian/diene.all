import { describe, it } from 'bun:test';
import 'should';
import {
  ConfigError,
  GitError,
  GitHubError,
  HookError,
  ReleaseError,
  ReleaserError,
  UnsupportedModuleError,
} from '../../src/lib/errors';
import { BumpError } from '../../src/lib/release/bump-presets';

describe('releaser errors', () => {
  it.each([
    ['ConfigError', (message: string) => new ConfigError(message)],
    ['UnsupportedModuleError', (message: string) => new UnsupportedModuleError(message)],
    ['GitError', (message: string) => new GitError(message)],
    ['HookError', (message: string) => new HookError(message)],
    ['GitHubError', (message: string) => new GitHubError(message)],
    ['BumpError', (message: string) => new BumpError(message)],
  ] as const)('should name a %s after its own class and keep it a ReleaserError', (expectedName, create) => {
    // Arrange
    const message = 'something failed';

    // Act
    const actual = create(message);

    // Assert
    actual.name.should.equal(expectedName);
    actual.message.should.equal(message);
    (actual instanceof ReleaserError).should.be.true();
    (actual instanceof Error).should.be.true();
  });

  it('should keep an UnsupportedModuleError a ConfigError', () => {
    // Arrange
    const message = 'unsupported module';

    // Act
    const actual = new UnsupportedModuleError(message);

    // Assert
    (actual instanceof ConfigError).should.be.true();
  });

  it('should carry the failing phase on a ReleaseError', () => {
    // Arrange
    const phase = 'prepare:beforeWrite';

    // Act
    const actual = new ReleaseError('release failed', phase);

    // Assert
    actual.name.should.equal('ReleaseError');
    actual.phase.should.equal(phase);
    actual.message.should.equal('release failed');
    (actual instanceof ReleaserError).should.be.true();
  });
});
