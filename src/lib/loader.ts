import { Err, Ok, type Result } from '@atomicloud/diene.result';
import { type Config, type ConfigData, FrozenConfig } from './config.js';
import { EnvOverrides } from './env.js';
import { BASE_LANDSCAPE, LandscapeResolver } from './landscape.js';
import { DeepMerger } from './merge.js';
import type { BlockShape, SchemaRegistry } from './registry.js';
import type { ConfigSource } from './source.js';
import { ConfigValidationError, ConfigValidator } from './validator.js';

interface LoadOptions {
  prefix: string;
  landscape?: string;
}

interface LoaderCollaborators {
  merger: DeepMerger;
  overrides: EnvOverrides;
  landscapes: LandscapeResolver;
  validator: ConfigValidator;
}

class ConfigLoaderError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'ConfigLoaderError';
  }
}

class ConfigLoader<S extends BlockShape> {
  constructor(
    private readonly source: ConfigSource,
    private readonly registry: SchemaRegistry<S>,
    private readonly options: LoadOptions,
    private readonly collaborators: LoaderCollaborators = {
      merger: new DeepMerger(),
      overrides: new EnvOverrides(),
      landscapes: new LandscapeResolver(),
      validator: new ConfigValidator(),
    },
  ) {
    if (options.prefix === '') throw new ConfigLoaderError('ConfigLoader requires a non-empty env-override prefix');
  }

  // Only the final merged layer is validated; a tier may be incomplete on its own.
  async load(): Promise<Config<S>> {
    const { merger, overrides, landscapes, validator } = this.collaborators;
    const { prefix, landscape } = this.options;
    const base = await this.source.base();
    const resolved = landscapes.resolve(landscape, base);
    const overlay = resolved === BASE_LANDSCAPE ? {} : await this.source.overlay(resolved);
    const withOverlay = merger.merge(base, overlay);
    const withBuildTime = overrides.apply(withOverlay, await this.source.buildTimeEnv(), prefix);
    const merged = overrides.apply(withBuildTime, await this.source.runtimeEnv(), prefix);
    return new FrozenConfig(validator.validate(this.registry.rootSchema(), merged) as ConfigData<S>);
  }

  // IO failures still throw; only validation failures become Err.
  async loadResult(): Promise<Result<Config<S>, ConfigValidationError>> {
    try {
      return Ok(await this.load());
    } catch (error) {
      if (error instanceof ConfigValidationError) return Err(error);
      throw error;
    }
  }
}

export type { LoaderCollaborators, LoadOptions };
export { ConfigLoader, ConfigLoaderError };
