import { Err, Ok, type Result } from '@atomicloud/diene.result';
import type { z } from 'zod';
import type { ErrorPortalConfig, Problem, ProblemDefinition, ProblemInit, RegisteredProblem } from './types.js';
import { ProblemTypeUriBuilder } from './uri.js';

export class ProblemRegistryError extends Error {
  constructor(
    readonly code: 'duplicate' | 'invalid' | 'unknown',
    message: string,
    options?: ErrorOptions,
  ) {
    super(message, options);
    this.name = 'ProblemRegistryError';
  }
}

export class ProblemStatusPolicy {
  // biome-ignore lint/complexity/noUselessConstructor: Bun coverage counts an implicit constructor as an uncovered function
  constructor() {}

  isStatus(value: unknown): value is number {
    return Number.isInteger(value) && (value as number) >= 100 && (value as number) <= 599;
  }

  assertStatus(value: number, subject: string): void {
    if (!this.isStatus(value)) {
      throw new ProblemRegistryError(
        'invalid',
        `${subject} must be an integer from 100 through 599; received ${value}`,
      );
    }
  }
}

export class ProblemFactory {
  constructor(private readonly statuses: ProblemStatusPolicy = new ProblemStatusPolicy()) {}

  createProblem<TSchema extends z.ZodType>(
    definition: RegisteredProblem<TSchema>,
    init: ProblemInit<z.input<TSchema>>,
  ): Problem<z.output<TSchema>> {
    const data = definition.dataSchema.parse(init.data);
    const status = init.status ?? definition.status;
    this.statuses.assertStatus(status, 'Problem status override');
    return {
      type: definition.type,
      title: definition.title,
      status,
      ...(init.detail === undefined ? {} : { detail: init.detail }),
      ...(init.instance === undefined ? {} : { instance: init.instance }),
      data,
    };
  }
}

export class ProblemRegistry {
  readonly portal: ErrorPortalConfig;
  readonly #entries = new Map<string, RegisteredProblem>();

  constructor(
    portal: ErrorPortalConfig,
    private readonly uris: ProblemTypeUriBuilder = new ProblemTypeUriBuilder(),
    private readonly statuses: ProblemStatusPolicy = new ProblemStatusPolicy(),
  ) {
    this.portal = Object.freeze({ ...portal });
  }

  register<TSchema extends z.ZodType>(definition: ProblemDefinition<TSchema>): RegisteredProblem<TSchema> {
    const key = this.key(definition.id, definition.version);
    if (this.#entries.has(key)) {
      throw new ProblemRegistryError(
        'duplicate',
        `Problem id ${definition.id} is already registered for version ${definition.version}`,
      );
    }
    const registered = this.bind(definition);
    this.#entries.set(key, registered);
    return registered;
  }

  tryRegister<TSchema extends z.ZodType>(
    definition: ProblemDefinition<TSchema>,
  ): Result<RegisteredProblem<TSchema>, ProblemRegistryError> {
    try {
      return Ok(this.register(definition));
    } catch (error: unknown) {
      return Err(error as ProblemRegistryError);
    }
  }

  get(id: string, version?: string): RegisteredProblem | undefined {
    if (version !== undefined) {
      return this.#entries.get(this.key(id, version));
    }

    const matches = [...this.#entries.values()].filter(entry => entry.id === id);
    if (matches.length > 1) {
      throw new ProblemRegistryError('invalid', `Problem id ${id} is ambiguous without a version`);
    }
    return matches[0];
  }

  require(id: string, version?: string): RegisteredProblem {
    const entry = this.get(id, version);
    if (entry === undefined) {
      const suffix = version === undefined ? '' : ` for version ${version}`;
      throw new ProblemRegistryError('unknown', `Problem id ${id} is not registered${suffix}`);
    }
    return entry;
  }

  list(): readonly RegisteredProblem[] {
    return [...this.#entries.values()].sort((left, right) =>
      left.version === right.version ? left.id.localeCompare(right.id) : left.version.localeCompare(right.version),
    );
  }

  private bind<TSchema extends z.ZodType>(definition: ProblemDefinition<TSchema>): RegisteredProblem<TSchema> {
    this.statuses.assertStatus(definition.status, 'Problem status');
    if (definition.title.trim() === '') {
      throw new ProblemRegistryError('invalid', 'Problem title must not be empty');
    }

    try {
      return Object.freeze({
        ...definition,
        type: this.uris.buildProblemTypeUri(this.portal, definition.version, definition.id),
      });
    } catch (error: unknown) {
      throw new ProblemRegistryError('invalid', `Invalid problem definition ${definition.id}`, { cause: error });
    }
  }

  private key(id: string, version: string): string {
    return `${version}:${id}`;
  }
}
