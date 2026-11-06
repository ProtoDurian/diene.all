import { stableConfig } from '@atomicloud/diene.core-utils';
import {
  type Problem,
  type ProblemDataInputOf,
  type ProblemDataOf,
  type ProblemDataSchema,
  ProblemFactory,
  ProblemGuard,
  type ProblemInit,
  type ProblemRegistry,
  type RegisteredProblem,
} from '@atomicloud/diene.problems';

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
  constructor(
    readonly actual: Problem,
    private readonly guard: ProblemGuard = new ProblemGuard(),
  ) {}

  toBe<TSchema extends ProblemDataSchema>(
    expected: RegisteredProblem<TSchema>,
    options: ProblemExpectationOptions = {},
  ): Problem<ProblemDataOf<TSchema>> {
    const actual: unknown = this.actual;
    if (!this.guard.isProblem(actual)) {
      throw new ProblemAssertionError([`expected a Problem, received ${this.display(actual)}`]);
    }

    const differences: string[] = [];
    const expectedStatus = options.status ?? expected.status;
    if (actual.type !== expected.type) {
      differences.push(`type expected ${expected.type}, received ${actual.type}`);
    }
    if (actual.title !== expected.title) {
      differences.push(`title expected ${expected.title}, received ${actual.title}`);
    }
    if (actual.status !== expectedStatus) {
      differences.push(`status expected ${expectedStatus}, received ${actual.status}`);
    }
    if (options.detail !== undefined && actual.detail !== options.detail) {
      differences.push(`detail expected ${this.display(options.detail)}, received ${this.display(actual.detail)}`);
    }
    if (options.instance !== undefined && actual.instance !== options.instance) {
      differences.push(
        `instance expected ${this.display(options.instance)}, received ${this.display(actual.instance)}`,
      );
    }

    if (expected.dataSchema === undefined) {
      if (actual.data !== undefined) {
        differences.push(`data expected absent, received ${this.display(actual.data)}`);
      }
    } else {
      const parsed = expected.dataSchema.safeParse(actual.data);
      if (!parsed.success) {
        differences.push(`data did not match registry schema: ${parsed.error.message}`);
      }
    }
    if (options.data !== undefined && this.display(actual.data) !== this.display(options.data)) {
      differences.push(`data expected ${this.display(options.data)}, received ${this.display(actual.data)}`);
    }

    if (differences.length > 0) {
      throw new ProblemAssertionError(differences);
    }
    return actual as Problem<ProblemDataOf<TSchema>>;
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
  constructor(
    private readonly factory: ProblemFactory = new ProblemFactory(),
    private readonly guard: ProblemGuard = new ProblemGuard(),
  ) {}

  expectProblem(actual: Problem): ProblemExpectation {
    return new ProblemExpectation(actual, this.guard);
  }

  buildProblem<TSchema extends ProblemDataSchema>(
    problem: RegisteredProblem<TSchema>,
    init: ProblemInit<ProblemDataInputOf<TSchema>>,
  ): Problem<ProblemDataOf<TSchema>> {
    return this.factory.createProblem(problem, init);
  }

  buildProblemFromRegistry(registry: ProblemRegistry, id: string, init: ProblemInit, version?: string): Problem {
    return this.factory.createProblem(registry.require(id, version), init);
  }
}
