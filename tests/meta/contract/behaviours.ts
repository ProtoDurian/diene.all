import { afterAll, describe, it } from 'bun:test';
import 'should';
import { z } from 'zod';
import { LandscapeResolutionError } from '../../../src/lib/landscape.js';
import { ConfigLoader } from '../../../src/lib/loader.js';
import { ConfigRegistry } from '../../../src/lib/registry.js';
import type { ConfigSource } from '../../../src/lib/source.js';
import { ConfigValidationError } from '../../../src/lib/validator.js';
import type { InMemoryTiers } from '../../../src/test-helper/index.js';

interface SourceFactory {
  readonly name: string;
  create(tiers: InMemoryTiers): Promise<ConfigSource>;
  dispose(): Promise<void>;
}

const registry = ConfigRegistry.create().register(
  'server',
  z.object({ port: z.number(), host: z.string(), tags: z.array(z.string()) }),
);

const BASE = { server: { port: 80, host: 'base', tags: ['a', 'b'] } };

const SCENARIOS: Array<{ label: string; tiers: InMemoryTiers; landscape?: string; expected: unknown }> = [
  { label: 'base defaults', tiers: { base: BASE }, expected: BASE },
  {
    label: 'the overlay over base',
    tiers: { base: BASE, overlays: { prod: { server: { host: 'prod' } } } },
    landscape: 'prod',
    expected: { server: { port: 80, host: 'prod', tags: ['a', 'b'] } },
  },
  {
    label: 'build-time over the overlay',
    tiers: {
      base: BASE,
      overlays: { prod: { server: { host: 'prod' } } },
      buildTimeEnv: { ATOMI_SERVER__HOST: 'build' },
    },
    landscape: 'prod',
    expected: { server: { port: 80, host: 'build', tags: ['a', 'b'] } },
  },
  {
    label: 'runtime env last with an indexed list key',
    tiers: {
      base: BASE,
      buildTimeEnv: { ATOMI_SERVER__PORT: '1' },
      runtimeEnv: { ATOMI_SERVER__PORT: '8080', ATOMI_SERVER__TAGS__1: 'z' },
    },
    expected: { server: { port: 8080, host: 'base', tags: ['a', 'z'] } },
  },
  {
    label: 'a blank runtime value as unset',
    tiers: { base: BASE, runtimeEnv: { ATOMI_SERVER__HOST: '' } },
    expected: BASE,
  },
  {
    label: 'base for a landscape with no overlay',
    tiers: { base: BASE },
    landscape: 'staging',
    expected: BASE,
  },
  {
    label: 'the overlay named by the service-tree app block',
    tiers: { base: { ...BASE, app: { landscape: 'prod' } }, overlays: { prod: { server: { host: 'prod' } } } },
    expected: { server: { port: 80, host: 'prod', tags: ['a', 'b'] } },
  },
];

const FAILURES: Array<{
  label: string;
  tiers: InMemoryTiers;
  landscape?: string;
  error: new (...args: never[]) => Error;
}> = [
  {
    label: 'an invalid final layer',
    tiers: { base: { server: { port: 'x', host: 'h', tags: [] } } },
    error: ConfigValidationError,
  },
  { label: 'an unsafe landscape', tiers: { base: BASE }, landscape: '../etc', error: LandscapeResolutionError },
];

const runContract = (factory: SourceFactory): void => {
  describe(`config source contract — ${factory.name}`, () => {
    afterAll(() => factory.dispose());

    it.each(SCENARIOS)('should load $label', async ({ tiers, landscape, expected }) => {
      // Arrange
      const source = await factory.create(tiers);

      // Act
      const config = await new ConfigLoader(source, registry, { prefix: 'ATOMI_', landscape }).load();

      // Assert
      config.all().should.deepEqual(expected);
    });

    it.each(FAILURES)('should reject $label', async ({ tiers, landscape, error }) => {
      // Arrange
      const source = await factory.create(tiers);

      // Act
      const act = new ConfigLoader(source, registry, { prefix: 'ATOMI_', landscape }).load();

      // Assert
      await act.should.be.rejectedWith(error);
    });
  });
};

export type { SourceFactory };
export { runContract };
