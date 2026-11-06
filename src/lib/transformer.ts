import { isRecord } from '@atomicloud/diene.core-utils';
import { ProblemFactory, ProblemStatusPolicy } from './registry.js';
import type { Problem, ProblemDataInputOf, ProblemDataSchema, ProblemInit, RegisteredProblem } from './types.js';

export class ProblemGuard {
  constructor(private readonly statuses: ProblemStatusPolicy = new ProblemStatusPolicy()) {}

  isProblem(value: unknown): value is Problem {
    return (
      isRecord(value) &&
      typeof value.type === 'string' &&
      typeof value.title === 'string' &&
      this.statuses.isStatus(value.status)
    );
  }
}

export interface ProblemTransformerOptions<TSchema extends ProblemDataSchema> {
  readonly fallback: RegisteredProblem<TSchema>;
  readonly fallbackData?: (error: unknown) => ProblemDataInputOf<TSchema>;
  readonly instance?: (error: unknown) => string | undefined;
}

export class ProblemTransformer<TSchema extends ProblemDataSchema> {
  constructor(
    readonly options: ProblemTransformerOptions<TSchema>,
    private readonly guard: ProblemGuard = new ProblemGuard(),
    private readonly factory: ProblemFactory = new ProblemFactory(),
    private readonly statuses: ProblemStatusPolicy = new ProblemStatusPolicy(),
  ) {}

  fromError(error: unknown): Problem {
    const visited = new Set<object>();
    let current = error;

    while (true) {
      if (this.guard.isProblem(current)) {
        return this.normalize(current, current.status);
      }
      if (isRecord(current)) {
        visited.add(current);
      }
      const nested = this.nestedError(current);
      if (nested === undefined || (isRecord(nested) && visited.has(nested))) {
        break;
      }
      current = nested;
    }

    return this.fallback(error, this.errorDetail(error));
  }

  async fromHttpError(response: Response): Promise<Problem> {
    const text = await response.text();
    const body = this.parseBody(text);
    const status = this.statuses.isStatus(response.status) ? response.status : undefined;

    const nested = this.nestedError(body);
    const found = this.guard.isProblem(body) ? body : this.guard.isProblem(nested) ? nested : undefined;
    if (found !== undefined) {
      return this.normalize(found, status ?? found.status);
    }

    const detail = text === '' ? response.statusText || 'HTTP request failed' : this.errorDetail(body);
    return this.fallback(body, detail, status);
  }

  private fallback(source: unknown, detail: string, status?: number): Problem {
    const init = {
      detail,
      status,
      instance: this.options.instance?.(source),
      data: this.options.fallbackData?.(source),
    } as ProblemInit<ProblemDataInputOf<TSchema>>;
    return this.factory.createProblem(this.options.fallback, init);
  }

  private normalize(problem: Problem, status: number): Problem {
    const { type, title, detail, instance, data } = problem;
    return {
      type,
      title,
      status,
      ...(typeof detail === 'string' ? { detail } : {}),
      ...(typeof instance === 'string' ? { instance } : {}),
      ...(data === undefined || data === null ? {} : { data }),
    };
  }

  private parseBody(text: string): unknown {
    try {
      return JSON.parse(text);
    } catch {
      return text;
    }
  }

  private nestedError(value: unknown): unknown {
    if (!isRecord(value)) {
      return undefined;
    }
    return value.problem ?? value.error ?? value.cause;
  }

  private errorDetail(value: unknown): string {
    if (value instanceof Error) {
      return value.message;
    }
    if (isRecord(value)) {
      if (typeof value.detail === 'string') {
        return value.detail;
      }
      if (typeof value.message === 'string') {
        return value.message;
      }
    }
    return typeof value === 'string' ? value : 'An unexpected error occurred';
  }
}
