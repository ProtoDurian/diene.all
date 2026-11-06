import type { Config } from '../lib/config.js';
import { ConfigLoader } from '../lib/loader.js';
import type { BlockShape, SchemaRegistry } from '../lib/registry.js';
import { InMemoryConfigSource, type InMemoryTiers } from './in-memory-source.js';

const DEFAULT_PREFIX = 'ATOMI_';

interface StubOptions {
  prefix?: string;
  landscape?: string;
}

class ConfigStubBuilder<S extends BlockShape> {
  constructor(
    private readonly registry: SchemaRegistry<S>,
    private readonly options: StubOptions = {},
  ) {}

  // Runs the real loader, so a stub can never drift from the registry.
  build(tiers: InMemoryTiers): Promise<Config<S>> {
    const { prefix = DEFAULT_PREFIX, landscape } = this.options;
    return new ConfigLoader(new InMemoryConfigSource(tiers), this.registry, { prefix, landscape }).load();
  }
}

export type { StubOptions };
export { ConfigStubBuilder };
