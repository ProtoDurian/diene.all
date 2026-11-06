import {
  type BlockShape,
  type Config,
  ConfigLoader,
  type ConfigRecord,
  type ConfigSource,
  ConfigValidationError,
  type EnvRecord,
  type SchemaRegistry,
} from '@atomicloud/diene.config';
import { isRecord } from '@atomicloud/diene.core-utils';

const DEFAULT_PREFIX = 'ATOMI_';

interface InMemoryTiers {
  base?: ConfigRecord;
  overlays?: Record<string, ConfigRecord>;
  buildTimeEnv?: EnvRecord;
  runtimeEnv?: EnvRecord;
}

interface StubOptions {
  prefix?: string;
  landscape?: string;
}

class TestHelperError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'TestHelperError';
  }
}

class InMemoryConfigSource implements ConfigSource {
  constructor(private readonly tiers: InMemoryTiers = {}) {}

  async base(): Promise<ConfigRecord> {
    return this.tiers.base ?? {};
  }

  async overlay(landscape: string): Promise<ConfigRecord> {
    return this.tiers.overlays?.[landscape] ?? {};
  }

  async buildTimeEnv(): Promise<EnvRecord> {
    return this.tiers.buildTimeEnv ?? {};
  }

  async runtimeEnv(): Promise<EnvRecord> {
    return this.tiers.runtimeEnv ?? {};
  }
}

class LandscapeConfigSource extends InMemoryConfigSource {
  constructor(landscape: string, tiers: InMemoryTiers = {}) {
    const app = isRecord(tiers.base?.app) ? tiers.base.app : {};
    super({ ...tiers, base: { ...tiers.base, app: { ...app, landscape } } });
  }
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

class ConfigAssertions<S extends BlockShape> {
  constructor(private readonly builder: ConfigStubBuilder<S>) {}

  async expectValid(tiers: InMemoryTiers): Promise<Config<S>> {
    try {
      return await this.builder.build(tiers);
    } catch (error) {
      const detail = error instanceof ConfigValidationError ? error.issues.join('; ') : String(error);
      throw new TestHelperError(`expected a valid config, but validation failed: ${detail}`);
    }
  }

  async expectInvalid(tiers: InMemoryTiers): Promise<ConfigValidationError> {
    try {
      await this.builder.build(tiers);
    } catch (error) {
      if (error instanceof ConfigValidationError) return error;
      throw new TestHelperError(`expected a ConfigValidationError, but got: ${String(error)}`);
    }
    throw new TestHelperError('expected config validation to fail, but it succeeded');
  }
}

export type { InMemoryTiers, StubOptions };
export { ConfigAssertions, ConfigStubBuilder, InMemoryConfigSource, LandscapeConfigSource, TestHelperError };
