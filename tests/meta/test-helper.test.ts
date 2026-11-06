import { describe, it } from 'bun:test';
import 'should';
import { z } from 'zod';
import { ConfigLoader } from '../../src/lib/loader.js';
import { ConfigRegistry } from '../../src/lib/registry.js';
import { ConfigValidationError } from '../../src/lib/validator.js';
import {
  ConfigAssertions,
  ConfigStubBuilder,
  InMemoryConfigSource,
  type InMemoryTiers,
  LandscapeConfigSource,
  TestHelperError,
} from '../../src/test-helper/index.js';

const registry = ConfigRegistry.create().register('server', z.object({ port: z.number(), host: z.string() }));
const GOOD: InMemoryTiers = { base: { server: { port: 80, host: 'h' } } };
const BAD: InMemoryTiers = { base: { server: { port: 'x', host: 'h' } } };

describe('InMemoryConfigSource', () => {
  it('should default every tier to empty', async () => {
    // Arrange
    const source = new InMemoryConfigSource();

    // Act
    const tiers = [
      await source.base(),
      await source.overlay('prod'),
      await source.buildTimeEnv(),
      await source.runtimeEnv(),
    ];

    // Assert
    tiers.should.deepEqual([{}, {}, {}, {}]);
  });

  it('should serve the provided tiers and an empty overlay for an unknown landscape', async () => {
    // Arrange
    const source = new InMemoryConfigSource({
      base: { a: 1 },
      overlays: { prod: { a: 2 } },
      buildTimeEnv: { ATOMI_A: '3' },
      runtimeEnv: { ATOMI_A: '4' },
    });

    // Act
    const tiers = [
      await source.base(),
      await source.overlay('prod'),
      await source.overlay('missing'),
      await source.buildTimeEnv(),
      await source.runtimeEnv(),
    ];

    // Assert
    tiers.should.deepEqual([{ a: 1 }, { a: 2 }, {}, { ATOMI_A: '3' }, { ATOMI_A: '4' }]);
  });
});

describe('LandscapeConfigSource', () => {
  it.each([
    { label: 'a source with no tiers', tiers: undefined, expected: { app: { landscape: 'prod' } } },
    {
      label: 'an existing app block',
      tiers: { base: { app: { team: 'core', landscape: 'old' }, server: { port: 1 } } },
      expected: { app: { team: 'core', landscape: 'prod' }, server: { port: 1 } },
    },
    { label: 'a non-object app value', tiers: { base: { app: 'x' } }, expected: { app: { landscape: 'prod' } } },
  ])('should stamp app.landscape onto $label', async ({ tiers, expected }) => {
    // Arrange
    const source = new LandscapeConfigSource('prod', tiers);

    // Act
    const base = await source.base();

    // Assert
    base.should.deepEqual(expected);
  });

  it('should make the real loader select its overlay with no explicit landscape', async () => {
    // Arrange
    const source = new LandscapeConfigSource('prod', { ...GOOD, overlays: { prod: { server: { host: 'prod' } } } });

    // Act
    const config = await new ConfigLoader(source, registry, { prefix: 'ATOMI_' }).load();

    // Assert
    config.get('server').should.deepEqual({ port: 80, host: 'prod' });
  });
});

describe('ConfigStubBuilder — invariants', () => {
  it.each([
    { label: 'base only', tiers: GOOD, options: { prefix: 'ATOMI_' }, expected: { port: 80, host: 'h' } },
    {
      label: 'a custom prefix',
      tiers: { ...GOOD, runtimeEnv: { X_SERVER__PORT: '9', ATOMI_SERVER__PORT: '1' } },
      options: { prefix: 'X_' },
      expected: { port: 9, host: 'h' },
    },
    {
      label: 'an explicit landscape',
      tiers: { ...GOOD, overlays: { prod: { server: { host: 'prod' } } } },
      options: { prefix: 'ATOMI_', landscape: 'prod' },
      expected: { port: 80, host: 'prod' },
    },
    {
      label: 'an app prefix, ignoring ATOMI_',
      tiers: { ...GOOD, runtimeEnv: { APP_SERVER__PORT: '7', ATOMI_SERVER__PORT: '1' } },
      options: { prefix: 'APP_' },
      expected: { port: 7, host: 'h' },
    },
  ])('should build a stub that passes the registry from $label', async ({ tiers, options, expected }) => {
    // Arrange
    const builder = new ConfigStubBuilder(registry, options);

    // Act
    const config = await builder.build(tiers);

    // Assert
    config.get('server').should.deepEqual(expected);
    registry.rootSchema().safeParse(config.all()).success.should.be.true();
  });

  it('should never hand back a stub that fails the registry', async () => {
    // Arrange
    const builder = new ConfigStubBuilder(registry, { prefix: 'ATOMI_' });

    // Act
    const act = builder.build(BAD);

    // Assert
    await act.should.be.rejectedWith(ConfigValidationError);
  });
});

describe('ConfigStubBuilder — required prefix', () => {
  it('should refuse to compile without a prefix', () => {
    // Arrange
    const options = {};

    // Act
    // @ts-expect-error the env prefix has no default
    const builder = new ConfigStubBuilder(registry, options);

    // Assert
    builder.should.be.instanceof(ConfigStubBuilder);
  });
});

describe('ConfigAssertions — assert the asserter', () => {
  const assertions = new ConfigAssertions(new ConfigStubBuilder(registry, { prefix: 'ATOMI_' }));
  const unsafe = new ConfigAssertions(new ConfigStubBuilder(registry, { prefix: 'ATOMI_', landscape: '../bad' }));

  it('expectValid should return the config on known-good tiers', async () => {
    // Arrange
    const tiers = GOOD;

    // Act
    const config = await assertions.expectValid(tiers);

    // Assert
    config.get('server').port.should.equal(80);
  });

  it.each([
    { label: 'known-bad tiers', subject: assertions, message: /validation failed: server\.port: / },
    {
      label: 'a non-validation error',
      subject: unsafe,
      message: /^expected a valid config, but loading failed: LandscapeResolutionError/,
    },
  ])('expectValid should fail with TestHelperError on $label', async ({ subject, message }) => {
    // Arrange
    const tiers = BAD;

    // Act
    const act = subject.expectValid(tiers);

    // Assert
    const error: object = await act.then(
      () => ({}),
      (reason: Error) => reason,
    );
    error.should.be.instanceof(TestHelperError);
    (error as TestHelperError).message.should.match(message);
  });

  it('expectInvalid should return the ConfigValidationError on known-bad tiers', async () => {
    // Arrange
    const tiers = BAD;

    // Act
    const error = await assertions.expectInvalid(tiers);

    // Assert
    error.issues.length.should.be.above(0);
  });

  it.each([
    {
      label: 'known-good tiers',
      subject: assertions,
      message: /^expected config validation to fail, but it succeeded$/,
    },
    { label: 'a non-validation error', subject: unsafe, message: /^expected a ConfigValidationError, but got: / },
  ])('expectInvalid should fail with TestHelperError on $label', async ({ subject, message }) => {
    // Arrange
    const tiers = GOOD;

    // Act
    const act = subject.expectInvalid(tiers);

    // Assert
    const error: object = await act.then(
      () => ({}),
      (reason: Error) => reason,
    );
    error.should.be.instanceof(TestHelperError);
    (error as TestHelperError).message.should.match(message);
  });
});
