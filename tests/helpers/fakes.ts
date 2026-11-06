import type { ICliIo } from '../../src/adapters/terminal/console-io';
import type { IPrompt } from '../../src/adapters/terminal/prompt';
import type { ISpinner } from '../../src/adapters/terminal/spinner';
import type { IKeyValueStore, IProgressReporter, IShell } from '../../src/lib/kv/interfaces';

export interface SetCall {
  readonly key: string;
  readonly value: string;
  readonly ttlSeconds: number | undefined;
}

export class FakeKeyValueStore implements IKeyValueStore {
  readonly setCalls: SetCall[] = [];
  readonly getCalls: string[] = [];
  readonly deleteCalls: string[] = [];
  closed = false;

  constructor(
    private readonly initial: Record<string, string> = {},
    private readonly failure?: Error,
  ) {}

  async set(key: string, value: string, ttlSeconds?: number): Promise<void> {
    if (this.failure) throw this.failure;
    this.setCalls.push({ key, value, ttlSeconds });
    this.initial[key] = value;
  }

  async get(key: string): Promise<string | null> {
    this.getCalls.push(key);
    if (this.failure) throw this.failure;
    const value = this.initial[key];
    return value === undefined ? null : value;
  }

  async delete(key: string): Promise<void> {
    if (this.failure) throw this.failure;
    this.deleteCalls.push(key);
    delete this.initial[key];
  }

  async close(): Promise<void> {
    this.closed = true;
  }
}

export interface CapturedIo extends ICliIo {
  readonly successes: string[];
  readonly warnings: string[];
  readonly errors: string[];
  readonly exitCodes: number[];
}

export function captureIo(): CapturedIo {
  const successes: string[] = [];
  const warnings: string[] = [];
  const errors: string[] = [];
  const exitCodes: number[] = [];
  return {
    successes,
    warnings,
    errors,
    exitCodes,
    success: (message: string): void => {
      successes.push(message);
    },
    warn: (message: string): void => {
      warnings.push(message);
    },
    error: (message: string): void => {
      errors.push(message);
    },
    setExitCode: (code: number): void => {
      exitCodes.push(code);
    },
    interactive: (): boolean => false,
  };
}

export interface CapturedSpinner extends ISpinner {
  readonly events: string[];
}

export function captureSpinner(): CapturedSpinner {
  const events: string[] = [];
  return {
    events,
    start: (text: string): void => {
      events.push(`start:${text}`);
    },
    succeed: (text: string): void => {
      events.push(`succeed:${text}`);
    },
    fail: (text: string): void => {
      events.push(`fail:${text}`);
    },
  };
}

export interface CapturedProgress extends IProgressReporter {
  readonly totals: number[];
  ticks: number;
  stopped: boolean;
}

export function captureProgress(): CapturedProgress {
  const reporter: CapturedProgress = {
    totals: [],
    ticks: 0,
    stopped: false,
    start: (total: number): void => {
      reporter.totals.push(total);
    },
    tick: (): void => {
      reporter.ticks += 1;
    },
    stop: (): void => {
      reporter.stopped = true;
    },
  };
  return reporter;
}

export class FakeShell implements IShell {
  constructor(private readonly result: string | Error) {}

  async platform(): Promise<string> {
    if (this.result instanceof Error) throw this.result;
    return this.result;
  }
}

export class FakePrompt implements IPrompt {
  constructor(private readonly answer: string) {}

  async ask(_message: string): Promise<string> {
    return this.answer;
  }
}
