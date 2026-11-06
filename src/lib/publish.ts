import { stableConfig } from '@atomicloud/diene.core-utils';
import { z } from 'zod';
import type { ProblemRegistry } from './registry.js';
import type { JsonSchema, ProblemManifest, ProblemManifestEntry, RegisteredProblem } from './types.js';

export class ProblemSchemaRenderer {
  // biome-ignore lint/complexity/noUselessConstructor: Bun coverage counts an implicit constructor as an uncovered function
  constructor() {}

  problemDataJsonSchema(problem: RegisteredProblem): JsonSchema {
    return stableConfig(z.toJSONSchema(problem.dataSchema, { target: 'draft-7' })) as JsonSchema;
  }
}

export class ProblemManifestEmitter {
  constructor(private readonly schemas: ProblemSchemaRenderer = new ProblemSchemaRenderer()) {}

  emitProblemManifest(registry: ProblemRegistry): ProblemManifest {
    const problems: ProblemManifestEntry[] = registry.list().map(problem => ({
      id: problem.id,
      type: problem.type,
      title: problem.title,
      status: problem.status,
      recoverable: problem.recoverable,
      version: problem.version,
      data: this.schemas.problemDataJsonSchema(problem),
    }));
    const schemas = Object.fromEntries(problems.map(problem => [problem.type, problem.data]));
    return {
      problems,
      schemas: stableConfig(schemas) as Readonly<Record<string, JsonSchema>>,
    };
  }
}
