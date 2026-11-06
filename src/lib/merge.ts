import { isRecord } from '@atomicloud/diene.core-utils';

type ConfigRecord = { [key: string]: unknown };

class DeepMerger {
  // biome-ignore lint/complexity/noUselessConstructor: Bun coverage counts an implicit constructor as an uncovered function
  constructor() {}

  // Arrays and scalars replace wholesale; per-index list overrides belong to the env tier.
  merge<T extends ConfigRecord>(base: T, override: ConfigRecord): T {
    const out: ConfigRecord = { ...base };
    for (const [key, value] of Object.entries(override)) {
      const existing = out[key];
      out[key] = isRecord(existing) && isRecord(value) ? this.merge(existing, value) : value;
    }
    return out as T;
  }
}

export type { ConfigRecord };
export { DeepMerger };
