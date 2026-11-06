import { afterAll, beforeAll, beforeEach, describe, it } from 'bun:test';
import 'should';
import { PgJobQueue, PgJobStore } from '../../../src/adapters/data/jobs/repo';
import { PgDatabase } from '../../../src/adapters/db/database';
import type { IDatabase, ISqlExecutor } from '../../../src/lib/db/interfaces';
import type { IJobHandler } from '../../../src/lib/jobs/interfaces';
import { JobRunner, JobScheduler, RetryPolicy } from '../../../src/lib/jobs/service';
import type { Job } from '../../../src/lib/jobs/structures';
import { PostgresFixture } from '../../support/postgres';

const JOBS = 60;

class CountingHandler implements IJobHandler {
  readonly runs = new Map<string, number>();

  constructor(readonly kind: string) {}

  async handle(job: Job): Promise<void> {
    this.runs.set(job.id, (this.runs.get(job.id) ?? 0) + 1);
    await Bun.sleep(2);
  }
}

class HeldClaimDatabase implements IDatabase {
  private held = true;

  constructor(
    private readonly inner: IDatabase,
    private readonly claimed: () => void,
    private readonly release: Promise<void>,
  ) {}

  withTenant<T>(tenantId: string, work: (sql: ISqlExecutor) => Promise<T>): Promise<T> {
    return this.inner.withTenant(tenantId, work);
  }

  withSystem<T>(work: (sql: ISqlExecutor) => Promise<T>): Promise<T> {
    if (!this.held) return this.inner.withSystem(work);
    this.held = false;
    return this.inner.withSystem(async sql => {
      const result = await work(sql);
      this.claimed();
      await this.release;
      return result;
    });
  }

  close(): Promise<void> {
    return this.inner.close();
  }
}

describe('JobRunner against Postgres (Testcontainers)', () => {
  let postgres: PostgresFixture;
  let left: PgDatabase;
  let right: PgDatabase;
  let tenant: string;

  beforeAll(async () => {
    postgres = await PostgresFixture.start();
    left = new PgDatabase({ connectionString: postgres.connectionString });
    right = new PgDatabase({ connectionString: postgres.connectionString });
    tenant = await postgres.createTenant('runner');
  }, 120_000);

  beforeEach(async () => {
    await postgres.admin(client => client.query('DELETE FROM jobs'));
  });

  afterAll(async () => {
    await left?.close();
    await right?.close();
    await postgres?.stop();
  }, 60_000);

  const enqueue = (count: number, outsideEffect: boolean, forkMode = false) =>
    left.withTenant(tenant, async sql => {
      const scheduler = new JobScheduler(new PgJobQueue(sql), forkMode);
      const jobs: Job[] = [];
      for (let index = 0; index < count; index++) {
        jobs.push(await scheduler.schedule({ kind: 'count', payload: { index }, outsideEffect }));
      }
      return jobs;
    });

  const waitingOnLock = () =>
    postgres.admin(async client => {
      const result = await client.query<{ waiting: number }>(
        "SELECT count(*)::int AS waiting FROM pg_stat_activity WHERE wait_event_type = 'Lock' AND datname = current_database()",
      );
      return (result.rows[0]?.waiting ?? 0) > 0;
    });

  const options = { batchSize: 3, maxBatches: 100, leaseSeconds: 60 };

  it('should run each job exactly once under two concurrent runners', async () => {
    // Arrange
    const jobs = await enqueue(JOBS, false);
    const handler = new CountingHandler('count');
    const runners = [left, right].map(
      db => new JobRunner(new PgJobStore(db), [handler], new RetryPolicy(), false, options),
    );

    // Act
    const summaries = await Promise.all(runners.map(runner => runner.drain()));

    // Assert
    [...handler.runs.values()].filter(count => count > 1).should.deepEqual([]);
    handler.runs.size.should.equal(jobs.length);
    summaries.reduce((total, summary) => total + summary.done, 0).should.equal(JOBS);
  }, 60_000);

  it('should never hand a job another runner holds to a second runner', async () => {
    // Arrange
    const jobs = await enqueue(4, false);
    const handler = new CountingHandler('count');
    const firstClaim = Promise.withResolvers<void>();
    const release = Promise.withResolvers<void>();
    const holding = new HeldClaimDatabase(left, firstClaim.resolve, release.promise);
    const first = new JobRunner(new PgJobStore(holding), [handler], new RetryPolicy(), false, {
      ...options,
      batchSize: 4,
    });
    const second = new JobRunner(new PgJobStore(right), [handler], new RetryPolicy(), false, {
      ...options,
      batchSize: 4,
    });

    // Act
    const firstDrain = first.drain();
    await firstClaim.promise;
    let secondDone = false;
    const secondDrain = second.drain().finally(() => {
      secondDone = true;
    });
    while (!secondDone && !(await waitingOnLock())) await Bun.sleep(20);
    release.resolve();
    await Promise.all([firstDrain, secondDrain]);

    // Assert
    [...handler.runs.values()].should.deepEqual(jobs.map(() => 1));
  }, 60_000);

  it('should hold outside-effect jobs in a fork and never run them', async () => {
    // Arrange
    await postgres.markFork();
    const copied = await enqueue(2, true);
    const scheduled = await enqueue(2, true, true);
    const handler = new CountingHandler('count');
    const runner = new JobRunner(new PgJobStore(left), [handler], new RetryPolicy(), true, options);

    // Act
    const summary = await runner.drain();
    const statuses = await postgres.admin(async client => {
      const result = await client.query<{ status: string }>('SELECT DISTINCT status FROM jobs');
      return result.rows.map(row => row.status);
    });

    // Assert
    scheduled.map(job => job.status).should.deepEqual(['held', 'held']);
    summary.held.should.equal(copied.length);
    handler.runs.size.should.equal(0);
    statuses.should.deepEqual(['held']);
  }, 60_000);
});
