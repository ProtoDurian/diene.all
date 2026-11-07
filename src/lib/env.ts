import { isRecord } from '@atomicloud/diene.core-utils';
import type { z } from 'zod';
import { EnvKeyMatcher, ScalarCoercer } from './coerce.js';
import { ConfigLoaderError } from './errors.js';
import type { ConfigRecord } from './merge.js';
import { type SchemaNode, SchemaWalker } from './schema-walker.js';
import type { EnvRecord } from './source.js';

const NESTING_SEPARATOR = '__';
const INDEX = /^\d+$/;
const MAX_INDEX = 4096;

type Container = ConfigRecord | unknown[];

interface Override {
  name: string;
  segments: readonly string[];
  raw: string;
}

class EnvOverrides {
  constructor(
    private readonly coercer: ScalarCoercer = new ScalarCoercer(),
    private readonly matcher: EnvKeyMatcher = new EnvKeyMatcher(),
    private readonly walker: SchemaWalker = new SchemaWalker(),
  ) {}

  apply(target: ConfigRecord, env: EnvRecord, prefix: string, schema?: z.ZodType): ConfigRecord {
    const result = structuredClone(target);
    const overrides = this.overrides(env, prefix).sort(
      (a, b) => a.segments.length - b.segments.length || a.name.localeCompare(b.name),
    );
    const root = this.walker.root(schema);
    for (const override of overrides) this.place(result, override.segments, override, root);
    return result;
  }

  keysFor(env: EnvRecord, prefix: string, path: readonly string[]): string[] {
    const wanted = path.map(segment => this.matcher.normalize(segment)).join(NESTING_SEPARATOR);
    return this.overrides(env, prefix)
      .filter(
        override =>
          override.segments.map(segment => this.matcher.normalize(segment)).join(NESTING_SEPARATOR) === wanted,
      )
      .map(override => override.name);
  }

  private overrides(env: EnvRecord, prefix: string): Override[] {
    return Object.entries(env).flatMap(([name, raw]) => {
      if (!name.startsWith(prefix) || raw === undefined || raw === '') return [];
      const segments = name.slice(prefix.length).split(NESTING_SEPARATOR);
      return segments.some(segment => segment === '') ? [] : [{ name, segments, raw }];
    });
  }

  private place(
    container: Container,
    segments: readonly string[],
    override: Override,
    node: SchemaNode,
    blind = false,
  ): void {
    const [head, next] = segments as [string, string | undefined];
    const nowBlind = blind || this.walker.opaque(node);
    const key = this.keyFor(container, head, override, node, nowBlind);
    const childSchema = this.walker.child(node, key);
    if (next === undefined) {
      this.assign(container, key, this.leaf(override, childSchema));
      return;
    }
    const existing = Array.isArray(container) ? container[key as number] : container[key];
    const child: Container =
      isRecord(existing) || Array.isArray(existing) ? existing : this.emptyFor(childSchema, next);
    this.assign(container, key, child);
    this.place(child, segments.slice(1), override, childSchema, nowBlind);
  }

  // z.coerce.boolean() would read any other text as true, so only true/false may reach a boolean without a .catch().
  private leaf(override: Override, node: SchemaNode): unknown {
    const kind = this.walker.kind(node);
    const value = this.coercer.coerceAs(override.raw, kind);
    if (kind === 'boolean' && typeof value !== 'boolean' && !this.walker.caught(node)) {
      throw new ConfigLoaderError(`${override.name}: expected true or false, got "${override.raw}"`);
    }
    return value;
  }

  private emptyFor(schema: SchemaNode, next: string): Container {
    const kind = this.walker.kind(schema);
    if (kind === 'array') return [];
    if (kind === 'object') return {};
    return INDEX.test(next) ? [] : {};
  }

  private keyFor(
    container: Container,
    segment: string,
    override: Override,
    node: SchemaNode,
    blind: boolean,
  ): string | number {
    if (Array.isArray(container)) {
      if (!INDEX.test(segment)) throw new ConfigLoaderError(`${override.name}: "${segment}" is not a list index`);
      const index = Number.parseInt(segment, 10);
      if (index > MAX_INDEX) throw new ConfigLoaderError(`${override.name}: list index ${index} exceeds ${MAX_INDEX}`);
      while (container.length <= index) container.push(undefined);
      return index;
    }
    const found =
      this.unique(this.walker.keys(node), segment, override) ?? this.unique(Object.keys(container), segment, override);
    if (found !== undefined) return found;
    if (blind) {
      throw new ConfigLoaderError(`${override.name}: "${segment}" sits under a schema the loader cannot walk`);
    }
    return segment.toLowerCase();
  }

  private unique(keys: readonly string[], segment: string, override: Override): string | undefined {
    const found = this.matcher.matches(keys, segment);
    if (found.length > 1)
      throw new ConfigLoaderError(`${override.name} matches more than one key: ${found.join(', ')}`);
    return found[0];
  }

  private assign(container: Container, key: string | number, value: unknown): void {
    if (Array.isArray(container)) container[key as number] = value;
    else container[key] = value;
  }
}

export { EnvOverrides, NESTING_SEPARATOR };
