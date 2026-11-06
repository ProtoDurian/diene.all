import type { z } from 'zod';

type LeafKind = 'string' | 'number' | 'boolean' | 'array' | 'object' | 'unknown';

type SchemaNode = readonly z.ZodType[];

interface Definition {
  type: string;
  innerType?: z.ZodType;
  in?: z.ZodType;
  getter?: () => z.ZodType;
  options?: readonly z.ZodType[];
  left?: z.ZodType;
  right?: z.ZodType;
  shape?: Record<string, z.ZodType>;
  catchall?: z.ZodType;
  element?: z.ZodType;
  items?: readonly z.ZodType[];
  rest?: z.ZodType | null;
  valueType?: z.ZodType;
  values?: readonly unknown[];
  entries?: Record<string, unknown>;
}

const WRAPPERS = new Set(['optional', 'nullable', 'default', 'prefault', 'readonly', 'catch', 'nonoptional']);
const OPAQUE = new Set(['custom', 'map', 'set', 'promise', 'function', 'transform', 'file']);
const KINDS: Record<string, LeafKind> = {
  string: 'string',
  bigint: 'string',
  date: 'string',
  number: 'number',
  boolean: 'boolean',
  array: 'array',
  tuple: 'array',
  object: 'object',
  record: 'object',
};
const VALUE_KINDS: Record<string, LeafKind> = {
  string: 'string',
  bigint: 'string',
  number: 'number',
  boolean: 'boolean',
};
const INDEX = /^\d+$/;

class SchemaWalker {
  // biome-ignore lint/complexity/noUselessConstructor: Bun coverage counts an implicit constructor as an uncovered function
  constructor() {}

  root(schema: z.ZodType | undefined): SchemaNode {
    return schema === undefined ? [] : [schema];
  }

  keys(node: SchemaNode): readonly string[] {
    return [...new Set(this.resolve(node).flatMap(definition => Object.keys(definition.shape ?? {})))];
  }

  child(node: SchemaNode, key: string | number): SchemaNode {
    return this.resolve(node).flatMap(definition => this.childOf(definition, String(key)));
  }

  kind(node: SchemaNode): LeafKind {
    const kinds = new Set(this.resolve(node).map(definition => this.kindOf(definition)));
    const [only] = kinds;
    return kinds.size === 1 && only !== undefined ? only : 'unknown';
  }

  opaque(node: SchemaNode): boolean {
    return this.resolve(node).some(definition => OPAQUE.has(definition.type));
  }

  private childOf(definition: Definition, key: string): z.ZodType[] {
    if (definition.type === 'array' && definition.element !== undefined) return [definition.element];
    if (definition.type === 'tuple') {
      if (!INDEX.test(key)) return [];
      const item = definition.items?.[Number.parseInt(key, 10)] ?? definition.rest;
      return item ? [item] : [];
    }
    if (definition.type === 'record' && definition.valueType !== undefined) return [definition.valueType];
    const member = definition.shape?.[key];
    if (member !== undefined) return [member];
    const catchall = definition.catchall;
    return catchall !== undefined && catchall._zod.def.type !== 'never' ? [catchall] : [];
  }

  private kindOf(definition: Definition): LeafKind {
    if (definition.type === 'literal') return this.valueKind(definition.values ?? []);
    if (definition.type === 'enum') return this.valueKind(this.enumValues(definition.entries ?? {}));
    return KINDS[definition.type] ?? 'unknown';
  }

  private valueKind(values: readonly unknown[]): LeafKind {
    const kinds = new Set(values.map(value => VALUE_KINDS[typeof value] ?? 'unknown'));
    const [only] = kinds;
    return kinds.size === 1 && only !== undefined ? only : 'unknown';
  }

  // A numeric TS enum also maps each number back to its name; those reverse entries are not values.
  private enumValues(entries: Record<string, unknown>): unknown[] {
    const numbers = new Set(
      Object.values(entries)
        .filter(value => typeof value === 'number')
        .map(String),
    );
    return Object.entries(entries)
      .filter(([key]) => !numbers.has(key))
      .map(([, value]) => value);
  }

  private resolve(node: SchemaNode): Definition[] {
    return node.flatMap(schema => {
      const definition = schema._zod.def as unknown as Definition;
      if (WRAPPERS.has(definition.type) && definition.innerType) return this.resolve([definition.innerType]);
      if (definition.type === 'pipe' && definition.in) return this.resolve([definition.in]);
      if (definition.type === 'lazy' && definition.getter) return this.resolve([definition.getter()]);
      if (definition.type === 'union') return this.resolve(definition.options ?? []);
      if (definition.type === 'intersection' && definition.left && definition.right) {
        return this.resolve([definition.left, definition.right]);
      }
      return [definition];
    });
  }
}

export type { LeafKind, SchemaNode };
export { SchemaWalker };
