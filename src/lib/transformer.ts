import { isRecord } from '@atomicloud/diene.core-utils';
import type { z } from 'zod';
import { ProblemFactory, ProblemStatusPolicy } from './registry.js';
import type { Problem, ProblemDataSchema, RegisteredProblem } from './types.js';

const UNEXPECTED_DETAIL = 'An unexpected error occurred';

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

export type ProblemTransformerOptions<TSchema extends ProblemDataSchema> = {
  readonly fallback: RegisteredProblem<TSchema>;
  readonly instance?: (error: unknown) => string | undefined;
} & (TSchema extends z.ZodType
  ? { readonly fallbackData: (error: unknown) => z.input<TSchema> }
  : { readonly fallbackData?: never });

interface ErrorScan {
  readonly problem?: Problem;
  readonly message?: string;
}

export class ProblemTransformer<TSchema extends ProblemDataSchema> {
  private readonly fallbackProblem: RegisteredProblem;
  private readonly fallbackData?: (error: unknown) => unknown;

  constructor(
    readonly options: ProblemTransformerOptions<TSchema>,
    private readonly guard: ProblemGuard = new ProblemGuard(),
    private readonly factory: ProblemFactory = new ProblemFactory(),
    private readonly statuses: ProblemStatusPolicy = new ProblemStatusPolicy(),
  ) {
    const widened: ProblemTransformerOptions<ProblemDataSchema> = options;
    const { fallback, fallbackData } = widened;
    if ((fallback.dataSchema === undefined) !== (fallbackData === undefined)) {
      const needs = fallback.dataSchema === undefined ? 'must not take' : 'needs';
      throw new TypeError(`Problem transformer fallback ${fallback.id} ${needs} a fallbackData mapper`);
    }
    this.fallbackProblem = fallback;
    this.fallbackData = fallbackData;
  }

  fromError(error: unknown): Problem {
    const scan = this.scan(error);
    if (scan.problem !== undefined) {
      return this.normalize(scan.problem, scan.problem.status);
    }
    return this.fallback(error, scan.message ?? UNEXPECTED_DETAIL);
  }

  async fromHttpError(response: Response): Promise<Problem> {
    const text = await response.text();
    const body = this.parseBody(text);
    const status = this.statuses.isStatus(response.status) ? response.status : undefined;

    const scan = this.scan(body);
    if (scan.problem !== undefined) {
      return this.normalize(scan.problem, status ?? scan.problem.status);
    }

    const detail = text === '' ? response.statusText || 'HTTP request failed' : (scan.message ?? UNEXPECTED_DETAIL);
    return this.fallback(body, detail, status);
  }

  private scan(value: unknown): ErrorScan {
    const visited = new Set<object>();
    let message: string | undefined;
    let current = value;

    while (true) {
      if (this.guard.isProblem(current)) {
        return { problem: current };
      }
      message ??= this.messageOf(current);
      if (isRecord(current)) {
        visited.add(current);
      }
      const nested = this.nestedError(current);
      if (nested === undefined || (isRecord(nested) && visited.has(nested))) {
        return { message };
      }
      current = nested;
    }
  }

  private fallback(source: unknown, detail: string, status?: number): Problem {
    return this.factory.createProblem(this.fallbackProblem, {
      detail,
      status,
      instance: this.options.instance?.(source),
      data: this.fallbackData?.(source),
    });
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

  private messageOf(value: unknown): string | undefined {
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
      return undefined;
    }
    return typeof value === 'string' ? value : undefined;
  }
}
