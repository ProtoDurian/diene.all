import type { z } from 'zod';
import type { BlockShape } from './registry.js';

type ConfigData<S extends BlockShape> = { [K in keyof S]: z.infer<S[K]> };

// Structural on purpose: each entry point bundles its own class declarations.
interface Config<S extends BlockShape> {
  get<K extends keyof S>(key: K): ConfigData<S>[K];
  all(): Readonly<ConfigData<S>>;
}

class FrozenConfig<S extends BlockShape> implements Config<S> {
  private readonly data: Readonly<ConfigData<S>>;

  constructor(data: ConfigData<S>) {
    this.data = Object.freeze({ ...data });
  }

  get<K extends keyof S>(key: K): ConfigData<S>[K] {
    return this.data[key];
  }

  all(): Readonly<ConfigData<S>> {
    return this.data;
  }
}

export type { Config, ConfigData };
export { FrozenConfig };
