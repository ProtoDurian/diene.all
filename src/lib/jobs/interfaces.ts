import type { Job, NewJob } from './structures';

export interface IJobQueue {
  enqueue(job: NewJob, status: 'queued' | 'held'): Promise<Job>;
}

export interface IJobStore {
  claim(limit: number, leaseSeconds: number): Promise<readonly Job[]>;
  complete(id: string): Promise<void>;
  retry(id: string, delaySeconds: number, error: string): Promise<void>;
  fail(id: string, error: string): Promise<void>;
  hold(id: string): Promise<void>;
}

export interface IJobHandler {
  readonly kind: string;
  handle(job: Job): Promise<void>;
}

export interface IJobKicker {
  kick(): void;
}
