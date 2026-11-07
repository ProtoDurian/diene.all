import { stableConfig } from '@atomicloud/diene.core-utils';
import { z } from 'zod';
import type { ProblemRegistry } from './registry.js';
import type { JsonSchema, ProblemDefinition, ProblemManifest, ProblemManifestEntry } from './types.js';

export class ProblemSchemaRenderer {
  // biome-ignore lint/complexity/noUselessConstructor: Bun coverage counts an implicit constructor as an uncovered function
  constructor() {}

  problemDataJsonSchema(problem: ProblemDefinition): JsonSchema {
    // A problem without data renders as `not: {}`: any present `data` member is invalid.
    const schema = problem.dataSchema ?? z.never();
    return stableConfig(z.toJSONSchema(schema, { target: 'draft-7' })) as JsonSchema;
  }
}

export class ProblemManifestEmitter {
  // biome-ignore lint/complexity/noUselessConstructor: Bun coverage counts an implicit constructor as an uncovered function
  constructor() {}

  emitProblemManifest(registry: ProblemRegistry): ProblemManifest {
    const problems: ProblemManifestEntry[] = registry.list().map(problem => ({
      id: problem.id,
      type: problem.type,
      title: problem.title,
      status: problem.status,
      recoverable: problem.recoverable,
      version: problem.version,
      data: problem.schema,
    }));
    const schemas = Object.fromEntries(problems.map(problem => [problem.type, problem.data]));
    return {
      problems,
      schemas: stableConfig(schemas) as Readonly<Record<string, JsonSchema>>,
    };
  }
}
