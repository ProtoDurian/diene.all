import { z } from 'zod';

const NUMERIC = /^-?\d+(?:\.\d+)?$/;
const SEPARATORS = /[_-]/g;

type Scalar = string | number | boolean;

class EnvKeyMatcher {
  // biome-ignore lint/complexity/noUselessConstructor: Bun coverage counts an implicit constructor as an uncovered function
  constructor() {}

  normalize(key: string): string {
    return key.replace(SEPARATORS, '').toLowerCase();
  }

  match(keys: readonly string[], segment: string): string {
    const target = this.normalize(segment);
    return keys.find(key => this.normalize(key) === target) ?? segment.toLowerCase();
  }
}

class ScalarCoercer {
  private readonly numbers = z.coerce.number();

  // biome-ignore lint/complexity/noUselessConstructor: Bun coverage counts an implicit constructor as an uncovered function
  constructor() {}

  coerce(raw: string): Scalar | undefined {
    if (raw === '') return undefined;
    const lowered = raw.toLowerCase();
    if (lowered === 'true') return true;
    if (lowered === 'false') return false;
    if (NUMERIC.test(raw)) {
      const parsed = this.numbers.safeParse(raw);
      if (parsed.success) return parsed.data;
    }
    return raw;
  }
}

export type { Scalar };
export { EnvKeyMatcher, ScalarCoercer };
