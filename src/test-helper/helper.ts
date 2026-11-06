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

interface InMemoryTiers {
  base?: ConfigRecord;
  overlays?: Record<string, ConfigRecord>;
  buildTimeEnv?: EnvRecord;
  runtimeEnv?: EnvRecord;
}

interface StubOptions {
  prefix: string;
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
    private readonly options: StubOptions,
  ) {}

  build(tiers: InMemoryTiers): Promise<Config<S>> {
    return new ConfigLoader(new InMemoryConfigSource(tiers), this.registry, this.options).load();
  }
}

class ConfigAssertions<S extends BlockShape> {
  constructor(private readonly builder: ConfigStubBuilder<S>) {}

  async expectValid(tiers: InMemoryTiers): Promise<Config<S>> {
    try {
      return await this.builder.build(tiers);
    } catch (error) {
      if (error instanceof ConfigValidationError) {
        throw new TestHelperError(`expected a valid config, but validation failed: ${error.issues.join('; ')}`);
      }
      throw new TestHelperError(`expected a valid config, but loading failed: ${String(error)}`);
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
