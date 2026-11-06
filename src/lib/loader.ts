import { Err, Ok, type Result } from '@atomicloud/diene.result';
import { type Config, type ConfigData, FrozenConfig } from './config.js';
import { EnvOverrides } from './env.js';
import { ConfigLoaderError } from './errors.js';
import { BASE_LANDSCAPE, LandscapeResolver } from './landscape.js';
import { DeepMerger } from './merge.js';
import type { BlockShape, SchemaRegistry } from './registry.js';
import type { ConfigSource, EnvRecord } from './source.js';
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

  async load(): Promise<Config<S>> {
    const { merger, overrides, landscapes, validator } = this.collaborators;
    const { prefix, landscape } = this.options;
    const schema = this.registry.rootSchema();
    const base = await this.source.base();
    const buildTimeEnv = await this.source.buildTimeEnv();
    const runtimeEnv = await this.source.runtimeEnv();
    this.refuseLandscapeOverride([buildTimeEnv, runtimeEnv]);
    const resolved = landscapes.resolve(landscape, base);
    const overlay = resolved === BASE_LANDSCAPE ? {} : await this.source.overlay(resolved);
    const withOverlay = merger.merge(base, overlay);
    const withBuildTime = overrides.apply(withOverlay, buildTimeEnv, prefix, schema);
    const merged = overrides.apply(withBuildTime, runtimeEnv, prefix, schema);
    return new FrozenConfig(validator.validate(schema, merged) as ConfigData<S>);
  }

  async loadResult(): Promise<Result<Config<S>, ConfigValidationError>> {
    try {
      return Ok(await this.load());
    } catch (error) {
      if (error instanceof ConfigValidationError) return Err(error);
      throw error;
    }
  }

  // The overlay is chosen before env applies, so an env landscape would load the wrong overlay.
  private refuseLandscapeOverride(tiers: readonly EnvRecord[]): void {
    const names = tiers.flatMap(env =>
      this.collaborators.overrides.keysFor(env, this.options.prefix, ['app', 'landscape']),
    );
    if (names.length > 0) {
      throw new ConfigLoaderError(
        `${names.join(', ')}: app.landscape cannot be set from env; pass the landscape to the loader`,
      );
    }
  }
}

export type { LoaderCollaborators, LoadOptions };
export { ConfigLoader };
