import type { z } from 'zod';
import type { BlockShape } from './registry.js';

type ConfigData<S extends BlockShape> = { [K in keyof S]: z.infer<S[K]> };

interface Config<S extends BlockShape> {
  get<K extends keyof S>(key: K): ConfigData<S>[K];
  all(): Readonly<ConfigData<S>>;
}

class FrozenConfig<S extends BlockShape> implements Config<S> {
  private readonly data: Readonly<ConfigData<S>>;

  constructor(data: ConfigData<S>) {
    this.data = this.freeze(data) as ConfigData<S>;
  }

  get<K extends keyof S>(key: K): ConfigData<S>[K] {
    return this.data[key];
  }

  all(): Readonly<ConfigData<S>> {
    return this.data;
  }

  // Copies plain objects and arrays so the caller's input stays mutable; other instances are kept as-is.
  private freeze(value: unknown): unknown {
    if (Array.isArray(value)) return Object.freeze(value.map(item => this.freeze(item)));
    if (typeof value !== 'object' || value === null) return value;
    const prototype = Object.getPrototypeOf(value);
    if (prototype !== Object.prototype && prototype !== null) return value;
    return Object.freeze(Object.fromEntries(Object.entries(value).map(([key, item]) => [key, this.freeze(item)])));
  }
}

export type { Config, ConfigData };
export { FrozenConfig };
