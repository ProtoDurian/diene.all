import type { RuntimeLog, WaitUntil } from '../../src/adapters/api/runtime';

export class BackgroundWork implements WaitUntil {
  private readonly pending: Promise<unknown>[] = [];

  waitUntil(promise: Promise<unknown>): void {
    this.pending.push(promise);
  }

  async settle(): Promise<void> {
    while (this.pending.length > 0) await Promise.all(this.pending.splice(0));
  }
}

export class RecordingLog implements RuntimeLog {
  readonly infos: { message: string; fields: Record<string, unknown> }[] = [];
  readonly errors: { message: string; fields: Record<string, unknown> }[] = [];

  info(message: string, fields: Record<string, unknown>): void {
    this.infos.push({ message, fields });
  }

  error(message: string, fields: Record<string, unknown>): void {
    this.errors.push({ message, fields });
  }
}
