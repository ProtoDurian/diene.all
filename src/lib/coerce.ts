import { z } from 'zod';
import type { LeafKind } from './schema-walker.js';

const NUMERIC = /^-?\d+(?:\.\d+)?$/;
const SEPARATORS = /[_-]/g;

type Scalar = string | number | boolean;

class EnvKeyMatcher {
  // biome-ignore lint/complexity/noUselessConstructor: Bun coverage counts an implicit constructor as an uncovered function
  constructor() {}

  normalize(key: string): string {
    return key.replace(SEPARATORS, '').toLowerCase();
  }

  matches(keys: readonly string[], segment: string): string[] {
    const target = this.normalize(segment);
    return [...new Set(keys)].filter(key => this.normalize(key) === target);
  }
}

class ScalarCoercer {
  private readonly numbers = z.coerce.number();

  // biome-ignore lint/complexity/noUselessConstructor: Bun coverage counts an implicit constructor as an uncovered function
  constructor() {}

  coerce(raw: string): Scalar | undefined {
    if (raw === '') return undefined;
    return this.toBoolean(raw) ?? this.toNumber(raw) ?? raw;
  }

  // A value the target type cannot take stays a string, so validation reports it.
  coerceAs(raw: string, kind: LeafKind): Scalar | undefined {
    if (raw === '') return undefined;
    if (kind === 'unknown') return this.coerce(raw);
    if (kind === 'number') return this.toNumber(raw) ?? raw;
    if (kind === 'boolean') return this.toBoolean(raw) ?? raw;
    return raw;
  }

  private toBoolean(raw: string): boolean | undefined {
    const lowered = raw.toLowerCase();
    if (lowered === 'true') return true;
    if (lowered === 'false') return false;
    return undefined;
  }

  private toNumber(raw: string): number | undefined {
    if (!NUMERIC.test(raw)) return undefined;
    const parsed = this.numbers.safeParse(raw);
    return parsed.success ? parsed.data : undefined;
  }
}

export type { Scalar };
export { EnvKeyMatcher, ScalarCoercer };
