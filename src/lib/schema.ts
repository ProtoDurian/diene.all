import { z } from 'zod';
import type { SchemaRegistry } from './registry.js';

interface SchemaGenOptions {
  id?: string;
}

class JsonSchemaGenerator {
  // biome-ignore lint/complexity/noUselessConstructor: Bun coverage counts an implicit constructor as an uncovered function
  constructor() {}

  generate(registry: SchemaRegistry, options: SchemaGenOptions = {}): Record<string, unknown> {
    const schema = z.toJSONSchema(registry.rootSchema(), { io: 'input' }) as Record<string, unknown>;
    return options.id === undefined ? schema : { $id: options.id, ...schema };
  }
}

export type { SchemaGenOptions };
export { JsonSchemaGenerator };
