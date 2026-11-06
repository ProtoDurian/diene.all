import { z } from 'zod';

type BlockShape = Record<string, z.ZodType>;

interface SchemaRegistry<S extends BlockShape = BlockShape> {
  rootSchema(): z.ZodObject<S>;
}

class ConfigRegistryError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'ConfigRegistryError';
  }
}

class ConfigRegistry<S extends BlockShape = BlockShape> implements SchemaRegistry<S> {
  private constructor(private readonly shape: S) {}

  static create(): ConfigRegistry<Record<string, never>> {
    return new ConfigRegistry<Record<string, never>>({});
  }

  register<K extends string, T extends z.ZodType>(key: K, schema: T): ConfigRegistry<S & Record<K, T>> {
    if (Object.hasOwn(this.shape, key)) throw new ConfigRegistryError(`config block "${key}" is already registered`);
    return new ConfigRegistry<S & Record<K, T>>({ ...this.shape, [key]: schema } as S & Record<K, T>);
  }

  get keys(): readonly string[] {
    return Object.keys(this.shape);
  }

  rootSchema(): z.ZodObject<S> {
    return z.object(this.shape);
  }
}

export type { BlockShape, SchemaRegistry };
export { ConfigRegistry, ConfigRegistryError };
