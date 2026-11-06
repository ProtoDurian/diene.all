import type { Config } from '../lib/config.js';
import type { BlockShape } from '../lib/registry.js';
import { ConfigValidationError } from '../lib/validator.js';
import type { InMemoryTiers } from './in-memory-source.js';
import type { ConfigStubBuilder } from './stub-builder.js';

class TestHelperError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'TestHelperError';
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

export { ConfigAssertions, TestHelperError };
