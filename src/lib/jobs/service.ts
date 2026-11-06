import type { IJobHandler, IJobQueue, IJobStore } from './interfaces';
import type { DrainOptions, DrainSummary, Job, NewJob } from './structures';

export class JobScheduler {
  constructor(
    private readonly queue: IJobQueue,
    private readonly forkMode: boolean,
  ) {}

  /** A fork never runs a job with outside effects, so it is stored held. */
  schedule(job: NewJob): Promise<Job> {
    return this.queue.enqueue(job, this.forkMode && job.outsideEffect ? 'held' : 'queued');
  }
}

export class RetryPolicy {
  constructor(
    private readonly maxAttempts = 5,
    private readonly baseSeconds = 30,
    private readonly maxSeconds = 3600,
  ) {}

  /** Seconds until the next attempt, or undefined once attempts are used up. */
  delay(attempts: number): number | undefined {
    if (attempts >= this.maxAttempts) return undefined;
    return Math.min(this.baseSeconds * 2 ** (attempts - 1), this.maxSeconds);
  }
}

export const DEFAULT_DRAIN_OPTIONS: DrainOptions = { batchSize: 10, maxBatches: 10, leaseSeconds: 300 };

export class JobRunner {
  constructor(
    private readonly store: IJobStore,
    private readonly handlers: readonly IJobHandler[],
    private readonly policy: RetryPolicy,
    private readonly forkMode: boolean,
    private readonly options: DrainOptions = DEFAULT_DRAIN_OPTIONS,
  ) {}

  async drain(): Promise<DrainSummary> {
    const totals = { done: 0, retried: 0, failed: 0, held: 0 };
    for (let batch = 0; batch < this.options.maxBatches; batch++) {
      const jobs = await this.store.claim(this.options.batchSize, this.options.leaseSeconds);
      for (const job of jobs) totals[await this.settle(job)]++;
      if (jobs.length < this.options.batchSize) break;
    }
    return totals;
  }

  private async settle(job: Job): Promise<keyof DrainSummary> {
    if (this.forkMode && job.outsideEffect) {
      await this.store.hold(job.id);
      return 'held';
    }
    const handler = this.handlers.find(candidate => candidate.kind === job.kind);
    if (handler === undefined) {
      await this.store.fail(job.id, `no handler for job kind ${job.kind}`);
      return 'failed';
    }
    try {
      await handler.handle(job);
      await this.store.complete(job.id);
      return 'done';
    } catch (error) {
      const reason = error instanceof Error ? error.message : String(error);
      const delay = this.policy.delay(job.attempts);
      if (delay === undefined) {
        await this.store.fail(job.id, reason);
        return 'failed';
      }
      await this.store.retry(job.id, delay, reason);
      return 'retried';
    }
  }
}
