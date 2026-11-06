import { isRecord } from '@atomicloud/diene.core-utils';
import { EnvKeyMatcher, ScalarCoercer } from './coerce.js';
import type { ConfigRecord } from './merge.js';
import type { EnvRecord } from './source.js';

const NESTING_SEPARATOR = '__';
const INDEX = /^\d+$/;
const MAX_INDEX = 4096;

type Container = ConfigRecord | unknown[];

class EnvOverrides {
  constructor(
    private readonly coercer: ScalarCoercer = new ScalarCoercer(),
    private readonly matcher: EnvKeyMatcher = new EnvKeyMatcher(),
  ) {}

  apply(target: ConfigRecord, env: EnvRecord, prefix: string): ConfigRecord {
    const result = structuredClone(target);
    for (const [rawKey, rawValue] of Object.entries(env)) {
      if (!rawKey.startsWith(prefix) || rawValue === undefined) continue;
      const value = this.coercer.coerce(rawValue);
      if (value === undefined) continue;
      const segments = rawKey.slice(prefix.length).split(NESTING_SEPARATOR);
      if (segments.some(segment => segment === '')) continue;
      this.place(result, segments, value);
    }
    return result;
  }

  private place(container: Container, segments: readonly string[], value: unknown): void {
    const [head, next] = segments as [string, string | undefined];
    const key = this.keyFor(container, head);
    if (key === undefined) return;
    if (next === undefined) {
      this.assign(container, key, value);
      return;
    }
    const existing = Array.isArray(container) ? container[key as number] : container[key];
    const child: Container = isRecord(existing) || Array.isArray(existing) ? existing : INDEX.test(next) ? [] : {};
    this.assign(container, key, child);
    this.place(child, segments.slice(1), value);
  }

  private keyFor(container: Container, segment: string): string | number | undefined {
    if (!Array.isArray(container)) return this.matcher.match(Object.keys(container), segment);
    if (!INDEX.test(segment)) return undefined;
    const index = Number.parseInt(segment, 10);
    if (index > MAX_INDEX) return undefined;
    while (container.length <= index) container.push(undefined);
    return index;
  }

  private assign(container: Container, key: string | number, value: unknown): void {
    if (Array.isArray(container)) container[key as number] = value;
    else container[key] = value;
  }
}

export { EnvOverrides, NESTING_SEPARATOR };
