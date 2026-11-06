import { describe, it } from 'bun:test';
import 'should';
import { z } from 'zod';
import { EnvOverrides } from '../../src/lib/env.js';
import { ConfigLoaderError } from '../../src/lib/errors.js';
import { LandscapeResolver } from '../../src/lib/landscape.js';
import { ConfigLoader } from '../../src/lib/loader.js';
import { DeepMerger } from '../../src/lib/merge.js';
import { ConfigRegistry } from '../../src/lib/registry.js';
import { ConfigValidationError, ConfigValidator } from '../../src/lib/validator.js';
import { FakeSource, type FakeTiers } from './support/fake-source.js';

const PREFIX = 'ATOMI_';
const valueRegistry = ConfigRegistry.create().register('server', z.object({ value: z.string() }));
const portRegistry = ConfigRegistry.create().register('server', z.object({ port: z.number() }));

type Tier = 'base' | 'overlay' | 'build' | 'runtime';

const tiersWith = (present: readonly Tier[]): FakeTiers => ({
  base: present.includes('base') ? { server: { value: 'base' } } : {},
  overlays: { prod: present.includes('overlay') ? { server: { value: 'overlay' } } : {} },
  buildTimeEnv: present.includes('build') ? { ATOMI_SERVER__VALUE: 'build' } : {},
  runtimeEnv: present.includes('runtime') ? { ATOMI_SERVER__VALUE: 'runtime' } : {},
});

class RecordingValidator extends ConfigValidator {
  readonly seen: unknown[] = [];

  override validate<T>(schema: z.ZodType<T>, value: unknown): T {
    this.seen.push(structuredClone(value));
    return super.validate(schema, value);
  }
}

describe('ConfigLoader.load — merge precedence across the 4 tiers', () => {
  it.each<{ present: Tier[]; expected: Tier }>([
    { present: ['base'], expected: 'base' },
    { present: ['overlay'], expected: 'overlay' },
    { present: ['build'], expected: 'build' },
    { present: ['runtime'], expected: 'runtime' },
    { present: ['base', 'overlay'], expected: 'overlay' },
    { present: ['base', 'build'], expected: 'build' },
    { present: ['base', 'runtime'], expected: 'runtime' },
    { present: ['overlay', 'build'], expected: 'build' },
    { present: ['overlay', 'runtime'], expected: 'runtime' },
    { present: ['build', 'runtime'], expected: 'runtime' },
    { present: ['base', 'overlay', 'build'], expected: 'build' },
    { present: ['base', 'overlay', 'runtime'], expected: 'runtime' },
    { present: ['base', 'build', 'runtime'], expected: 'runtime' },
    { present: ['overlay', 'build', 'runtime'], expected: 'runtime' },
    { present: ['base', 'overlay', 'build', 'runtime'], expected: 'runtime' },
  ])('should let $expected win when $present set the key', async ({ present, expected }) => {
    // Arrange
    const loader = new ConfigLoader(new FakeSource(tiersWith(present)), valueRegistry, {
      prefix: PREFIX,
      landscape: 'prod',
    });

    // Act
    const config = await loader.load();

    // Assert
    config.get('server').value.should.equal(expected);
  });

  it('should keep each lower-tier key that no higher tier overrides', async () => {
    // Arrange
    const registry = ConfigRegistry.create().register(
      'server',
      z.object({ a: z.string(), b: z.string(), c: z.string(), d: z.string() }),
    );
    const source = new FakeSource({
      base: { server: { a: 'base', b: 'base', c: 'base', d: 'base' } },
      overlays: { prod: { server: { b: 'overlay', c: 'overlay', d: 'overlay' } } },
      buildTimeEnv: { ATOMI_SERVER__C: 'build', ATOMI_SERVER__D: 'build' },
      runtimeEnv: { ATOMI_SERVER__D: 'runtime' },
    });

    // Act
    const config = await new ConfigLoader(source, registry, { prefix: PREFIX, landscape: 'prod' }).load();

    // Assert
    config.all().should.deepEqual({ server: { a: 'base', b: 'overlay', c: 'build', d: 'runtime' } });
  });
});

describe('ConfigLoader.load — landscape selection', () => {
  it.each([
    { label: 'no overlay read for base', tiers: {}, landscape: undefined, expected: [] },
    { label: 'the explicit landscape', tiers: {}, landscape: 'prod', expected: ['prod'] },
    {
      label: 'the service-tree landscape',
      tiers: { base: { app: { landscape: 'stage' } } },
      landscape: undefined,
      expected: ['stage'],
    },
  ])('should read $label', async ({ tiers, landscape, expected }) => {
    // Arrange
    const source = new FakeSource(tiers);
    const loader = new ConfigLoader(source, ConfigRegistry.create(), { prefix: PREFIX, landscape });

    // Act
    await loader.load();

    // Assert
    source.overlayCalls.should.deepEqual(expected);
  });
});

describe('ConfigLoader.load — fail-fast on the final layer only', () => {
  it('should validate once, on the final merged layer, never on an intermediate tier', async () => {
    // Arrange
    const validator = new RecordingValidator();
    const source = new FakeSource({
      base: { server: {} },
      overlays: { prod: { server: { port: 'not-a-number' } } },
      buildTimeEnv: { ATOMI_SERVER__PORT: 'still-bad' },
      runtimeEnv: { ATOMI_SERVER__PORT: '8080' },
    });
    const collaborators = {
      merger: new DeepMerger(),
      overrides: new EnvOverrides(),
      landscapes: new LandscapeResolver(),
      validator,
    };
    const loader = new ConfigLoader(source, portRegistry, { prefix: PREFIX, landscape: 'prod' }, collaborators);

    // Act
    const config = await loader.load();

    // Assert
    validator.seen.should.deepEqual([{ server: { port: 8080 } }]);
    config.get('server').port.should.equal(8080);
  });

  it.each([
    { label: 'a wrong type', tiers: { base: { server: { port: 'x' } } } },
    {
      label: 'a missing secret left blank in yaml and env',
      tiers: { base: { server: {} }, runtimeEnv: { ATOMI_SERVER__PORT: '' } },
    },
  ])('should reject $label with ConfigValidationError', async ({ tiers }) => {
    // Arrange
    const loader = new ConfigLoader(new FakeSource(tiers), portRegistry, { prefix: PREFIX });

    // Act
    const act = loader.load();

    // Assert
    await act.should.be.rejectedWith(ConfigValidationError);
  });
});

describe('ConfigLoader.loadResult', () => {
  it('should return Ok with the config when valid', async () => {
    // Arrange
    const loader = new ConfigLoader(new FakeSource({ base: { server: { port: 1 } } }), portRegistry, {
      prefix: PREFIX,
    });

    // Act
    const result = await loader.loadResult();

    // Assert
    (await result.isOk()).should.be.true();
    (await result.unwrap()).get('server').port.should.equal(1);
  });

  it('should return Err on a validation failure', async () => {
    // Arrange
    const loader = new ConfigLoader(new FakeSource({ base: { server: { port: 'x' } } }), portRegistry, {
      prefix: PREFIX,
    });

    // Act
    const result = await loader.loadResult();

    // Assert
    (await result.unwrapErr()).should.be.instanceof(ConfigValidationError);
  });

  it('should rethrow a non-validation error', async () => {
    // Arrange
    const loader = new ConfigLoader(new FakeSource({ failBase: new Error('disk gone') }), portRegistry, {
      prefix: PREFIX,
    });

    // Act
    const act = loader.loadResult();

    // Assert
    await act.should.be.rejectedWith('disk gone');
  });
});

describe('ConfigLoader construction', () => {
  it('should reject an empty prefix', () => {
    // Arrange
    const source = new FakeSource({});

    // Act
    const act = () => new ConfigLoader(source, ConfigRegistry.create(), { prefix: '' });

    // Assert
    act.should.throw(ConfigLoaderError);
  });
});

describe('ConfigLoader.load — env overrides follow the registry schema', () => {
  it('should keep an all-digit secret a string and reach a camelCase key absent from yaml', async () => {
    // Arrange
    const registry = ConfigRegistry.create()
      .register('db', z.object({ password: z.string().min(1) }))
      .register('svc', z.object({ maxRetries: z.number().optional() }));
    const source = new FakeSource({
      base: { db: { password: '' }, svc: {} },
      runtimeEnv: { ATOMI_DB__PASSWORD: '123456', ATOMI_SVC__MAX_RETRIES: '3' },
    });

    // Act
    const config = await new ConfigLoader(source, registry, { prefix: PREFIX }).load();

    // Assert
    config.all().should.deepEqual({ db: { password: '123456' }, svc: { maxRetries: 3 } });
  });

  it('should reject a secret left blank in yaml and env when declared min(1)', async () => {
    // Arrange
    const registry = ConfigRegistry.create().register('db', z.object({ password: z.string().min(1) }));
    const source = new FakeSource({ base: { db: { password: '' } }, runtimeEnv: { ATOMI_DB__PASSWORD: '' } });

    // Act
    const act = new ConfigLoader(source, registry, { prefix: PREFIX }).load();

    // Assert
    await act.should.be.rejectedWith({ name: 'ConfigValidationError', message: /db\.password/ });
  });
});

describe('ConfigLoader.load — landscape guards', () => {
  it('should treat a blank explicit landscape as unset and use app.landscape', async () => {
    // Arrange
    const source = new FakeSource({ base: { app: { landscape: 'prod' } } });

    // Act
    await new ConfigLoader(source, ConfigRegistry.create(), { prefix: PREFIX, landscape: '' }).load();

    // Assert
    source.overlayCalls.should.deepEqual(['prod']);
  });

  it.each([
    { tier: 'runtime', tiers: { runtimeEnv: { ATOMI_APP__LANDSCAPE: 'prod' } }, name: /ATOMI_APP__LANDSCAPE/ },
    { tier: 'build-time', tiers: { buildTimeEnv: { ATOMI_app__Landscape: 'prod' } }, name: /ATOMI_app__Landscape/ },
  ])('should refuse a $tier env override of app.landscape', async ({ tiers, name }) => {
    // Arrange
    const loader = new ConfigLoader(new FakeSource(tiers), ConfigRegistry.create(), { prefix: PREFIX });

    // Act
    const act = loader.load();

    // Assert
    await act.should.be.rejectedWith({ name: 'ConfigLoaderError', message: name });
  });
});
