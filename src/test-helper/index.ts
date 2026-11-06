import { stableConfig } from '@atomicloud/diene.core-utils';
import {
  type Problem,
  ProblemFactory,
  type ProblemInit,
  type ProblemRegistry,
  type RegisteredProblem,
} from '@atomicloud/diene.problems';
import type { z } from 'zod';

export class ProblemAssertionError extends Error {
  constructor(readonly differences: readonly string[]) {
    super(['Problem assertion failed:', ...differences.map(difference => `- ${difference}`)].join('\n'));
    this.name = 'ProblemAssertionError';
  }
}

export interface ProblemExpectationOptions {
  readonly status?: number;
  readonly detail?: string;
  readonly instance?: string;
  readonly data?: unknown;
}

export class ProblemExpectation {
  constructor(readonly actual: Problem) {}

  toBe<TSchema extends z.ZodType>(
    expected: RegisteredProblem<TSchema>,
    options: ProblemExpectationOptions = {},
  ): Problem<z.output<TSchema>> {
    const differences: string[] = [];
    const expectedStatus = options.status ?? expected.status;

    if (this.actual.type !== expected.type) {
      differences.push(`type expected ${expected.type}, received ${this.actual.type}`);
    }
    if (this.actual.title !== expected.title) {
      differences.push(`title expected ${expected.title}, received ${this.actual.title}`);
    }
    if (this.actual.status !== expectedStatus) {
      differences.push(`status expected ${expectedStatus}, received ${this.actual.status}`);
    }
    if (options.detail !== undefined && this.actual.detail !== options.detail) {
      differences.push(`detail expected ${this.display(options.detail)}, received ${this.display(this.actual.detail)}`);
    }
    if (options.instance !== undefined && this.actual.instance !== options.instance) {
      differences.push(
        `instance expected ${this.display(options.instance)}, received ${this.display(this.actual.instance)}`,
      );
    }

    const parsed = expected.dataSchema.safeParse(this.actual.data);
    if (!parsed.success) {
      differences.push(`data did not match registry schema: ${parsed.error.message}`);
    }
    if (options.data !== undefined && this.display(this.actual.data) !== this.display(options.data)) {
      differences.push(`data expected ${this.display(options.data)}, received ${this.display(this.actual.data)}`);
    }

    if (differences.length > 0) {
      throw new ProblemAssertionError(differences);
    }
    return this.actual as Problem<z.output<TSchema>>;
  }

  private display(value: unknown): string {
    try {
      return JSON.stringify(stableConfig(value), null, 2) ?? String(value);
    } catch {
      return String(value);
    }
  }
}

export class ProblemTestHelper {
  constructor(private readonly factory: ProblemFactory = new ProblemFactory()) {}

  expectProblem(actual: Problem): ProblemExpectation {
    return new ProblemExpectation(actual);
  }

  buildProblem<TSchema extends z.ZodType>(
    problem: RegisteredProblem<TSchema>,
    init: ProblemInit<z.input<TSchema>>,
  ): Problem<z.output<TSchema>> {
    return this.factory.createProblem(problem, init);
  }

  buildProblemFromRegistry(
    registry: ProblemRegistry,
    id: string,
    init: ProblemInit<unknown>,
    version?: string,
  ): Problem {
    return this.factory.createProblem(registry.require(id, version), init);
  }
}
