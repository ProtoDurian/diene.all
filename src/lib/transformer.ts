import { isRecord } from '@atomicloud/diene.core-utils';
import type { z } from 'zod';
import { ProblemFactory, ProblemStatusPolicy } from './registry.js';
import type { Problem, RegisteredProblem } from './types.js';

export class ProblemGuard {
  constructor(private readonly statuses: ProblemStatusPolicy = new ProblemStatusPolicy()) {}

  isProblem(value: unknown): value is Problem {
    return (
      isRecord(value) &&
      typeof value.type === 'string' &&
      typeof value.title === 'string' &&
      this.statuses.isStatus(value.status) &&
      'data' in value
    );
  }
}

export interface ProblemTransformerOptions<TSchema extends z.ZodType> {
  readonly fallback: RegisteredProblem<TSchema>;
  readonly fallbackData: (error: unknown) => z.input<TSchema>;
  readonly instance?: (error: unknown) => string | undefined;
}

export class ProblemTransformer<TSchema extends z.ZodType> {
  constructor(
    readonly options: ProblemTransformerOptions<TSchema>,
    private readonly guard: ProblemGuard = new ProblemGuard(),
    private readonly factory: ProblemFactory = new ProblemFactory(),
  ) {}

  fromError(error: unknown): Problem {
    const visited = new Set<object>();
    let current = error;

    while (true) {
      if (this.guard.isProblem(current)) {
        return current;
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

    return this.factory.createProblem(this.options.fallback, {
      detail: this.errorDetail(current),
      instance: this.options.instance?.(current),
      data: this.options.fallbackData(current),
    });
  }

  async fromHttpError(response: Response): Promise<Problem> {
    const text = await response.text();
    const body = this.parseBody(text);

    if (this.guard.isProblem(body)) {
      return { ...body, status: response.status };
    }

    const nested = this.nestedError(body);
    if (this.guard.isProblem(nested)) {
      return { ...nested, status: response.status };
    }

    return this.factory.createProblem(this.options.fallback, {
      detail: text === '' ? response.statusText || 'HTTP request failed' : this.errorDetail(body),
      status: response.status,
      instance: response.url || this.options.instance?.(body),
      data: this.options.fallbackData(body),
    });
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
