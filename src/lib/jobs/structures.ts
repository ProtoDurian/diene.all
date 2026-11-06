export type JobStatus = 'queued' | 'running' | 'done' | 'failed' | 'held';

export interface NewJob {
  readonly kind: string;
  readonly payload: Readonly<Record<string, unknown>>;
  readonly outsideEffect: boolean;
}

export interface Job extends NewJob {
  readonly id: string;
  readonly tenantId: string;
  readonly status: JobStatus;
  readonly runAt: Date;
  readonly attempts: number;
  readonly lockedUntil?: Date;
  readonly lastError?: string;
}

export interface DrainSummary {
  readonly done: number;
  readonly retried: number;
  readonly failed: number;
  readonly held: number;
}

export interface DrainOptions {
  readonly batchSize: number;
  readonly maxBatches: number;
  readonly leaseSeconds: number;
}
