import type { z } from 'zod';

type LeafKind = 'string' | 'number' | 'boolean' | 'array' | 'object' | 'unknown';

interface Definition {
  type: string;
  innerType?: z.ZodType;
  in?: z.ZodType;
  getter?: () => z.ZodType;
  shape?: Record<string, z.ZodType>;
  element?: z.ZodType;
  values?: readonly unknown[];
}

const WRAPPERS = new Set(['optional', 'nullable', 'default', 'prefault', 'readonly', 'catch', 'nonoptional']);
const KINDS: Record<string, LeafKind> = {
  string: 'string',
  enum: 'string',
  bigint: 'string',
  date: 'string',
  number: 'number',
  boolean: 'boolean',
  array: 'array',
  object: 'object',
};

class SchemaWalker {
  // biome-ignore lint/complexity/noUselessConstructor: Bun coverage counts an implicit constructor as an uncovered function
  constructor() {}

  keys(schema: z.ZodType | undefined): readonly string[] {
    return Object.keys(this.definition(schema)?.shape ?? {});
  }

  child(schema: z.ZodType | undefined, key: string | number): z.ZodType | undefined {
    const definition = this.definition(schema);
    if (definition?.type === 'array') return definition.element;
    return typeof key === 'string' ? definition?.shape?.[key] : undefined;
  }

  kind(schema: z.ZodType | undefined): LeafKind {
    const definition = this.definition(schema);
    if (definition === undefined) return 'unknown';
    if (definition.type === 'literal') {
      const kinds = new Set((definition.values ?? []).map(value => typeof value));
      const [only] = kinds;
      return kinds.size === 1 && only !== undefined ? (KINDS[only] ?? 'unknown') : 'unknown';
    }
    return KINDS[definition.type] ?? 'unknown';
  }

  private definition(schema: z.ZodType | undefined): Definition | undefined {
    let current = schema;
    while (current !== undefined) {
      const definition = current._zod.def as unknown as Definition;
      if (WRAPPERS.has(definition.type)) current = definition.innerType;
      else if (definition.type === 'pipe') current = definition.in;
      else if (definition.type === 'lazy') current = definition.getter?.();
      else return definition;
    }
    return undefined;
  }
}

export type { LeafKind };
export { SchemaWalker };
