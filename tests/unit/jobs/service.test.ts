import { describe, it } from 'bun:test';
import 'should';
import type { IJobHandler, IJobQueue, IJobStore } from '../../../src/lib/jobs/interfaces';
import { JobRunner, JobScheduler, RetryPolicy } from '../../../src/lib/jobs/service';
import type { Job, NewJob } from '../../../src/lib/jobs/structures';

const job = (overrides: Partial<Job> = {}): Job => ({
  id: crypto.randomUUID(),
  tenantId: 'tenant-a',
  kind: 'work',
  payload: {},
  outsideEffect: false,
  status: 'running',
  runAt: new Date('2024-03-15T14:30:00.000Z'),
  attempts: 1,
  ...overrides,
});

class RecordingQueue implements IJobQueue {
  readonly statuses: string[] = [];

  async enqueue(input: NewJob, status: 'queued' | 'held'): Promise<Job> {
    this.statuses.push(status);
    return job({ ...input, status });
  }
}

class ScriptedStore implements IJobStore {
  readonly events: string[] = [];
  claims = 0;

  constructor(private readonly batches: Job[][]) {}

  async claim(limit: number): Promise<readonly Job[]> {
    this.claims++;
    return (this.batches.shift() ?? []).slice(0, limit);
  }

  async complete(id: string): Promise<void> {
    this.events.push(`done:${id}`);
  }

  async retry(id: string, delaySeconds: number, error: string): Promise<void> {
    this.events.push(`retry:${id}:${delaySeconds}:${error}`);
  }

  async fail(id: string, error: string): Promise<void> {
    this.events.push(`fail:${id}:${error}`);
  }

  async hold(id: string): Promise<void> {
    this.events.push(`hold:${id}`);
  }
}

class Handler implements IJobHandler {
  readonly seen: string[] = [];

  constructor(
    readonly kind: string,
    private readonly outcome: () => void = () => undefined,
  ) {}

  async handle(input: Job): Promise<void> {
    this.seen.push(input.id);
    this.outcome();
  }
}

describe('JobScheduler', () => {
  it.each([
    { forkMode: false, outsideEffect: true, expected: 'queued' },
    { forkMode: false, outsideEffect: false, expected: 'queued' },
    { forkMode: true, outsideEffect: false, expected: 'queued' },
    { forkMode: true, outsideEffect: true, expected: 'held' },
  ])('should store fork=$forkMode outsideEffect=$outsideEffect as $expected', async ({
    forkMode,
    outsideEffect,
    expected,
  }) => {
    // Arrange
    const queue = new RecordingQueue();
    const subject = new JobScheduler(queue, forkMode);

    // Act
    const actual = await subject.schedule({ kind: 'mail.send', payload: {}, outsideEffect });

    // Assert
    actual.status.should.equal(expected);
    queue.statuses.should.deepEqual([expected]);
  });
});

describe('RetryPolicy', () => {
  it.each([
    { attempts: 1, expected: 30 },
    { attempts: 2, expected: 60 },
    { attempts: 4, expected: 240 },
  ])('should wait $expected seconds after attempt $attempts', ({ attempts, expected }) => {
    // Arrange
    const subject = new RetryPolicy();

    // Act
    const actual = subject.delay(attempts);

    // Assert
    (actual as number).should.equal(expected);
  });

  it('should cap the delay at the maximum', () => {
    // Arrange
    const subject = new RetryPolicy(20, 30, 100);

    // Act
    const actual = subject.delay(10);

    // Assert
    (actual as number).should.equal(100);
  });

  it('should stop retrying once attempts are used up', () => {
    // Arrange
    const subject = new RetryPolicy(3);

    // Act
    const actual = subject.delay(3);

    // Assert
    (actual === undefined).should.be.true();
  });
});

describe('JobRunner', () => {
  const options = { batchSize: 2, maxBatches: 3, leaseSeconds: 60 };

  it('should run every claimed job once and mark it done', async () => {
    // Arrange
    const [first, second, third] = [job(), job(), job()];
    const store = new ScriptedStore([[first, second], [third]]);
    const handler = new Handler('work');
    const subject = new JobRunner(store, [handler], new RetryPolicy(), false, options);

    // Act
    const actual = await subject.drain();

    // Assert
    actual.should.deepEqual({ done: 3, retried: 0, failed: 0, held: 0 });
    handler.seen.should.deepEqual([first.id, second.id, third.id]);
    store.claims.should.equal(2);
  });

  it('should stop after the batch limit even when more work is waiting', async () => {
    // Arrange
    const store = new ScriptedStore([
      [job(), job()],
      [job(), job()],
      [job(), job()],
      [job(), job()],
    ]);
    const subject = new JobRunner(store, [new Handler('work')], new RetryPolicy(), false, options);

    // Act
    const actual = await subject.drain();

    // Assert
    actual.done.should.equal(6);
    store.claims.should.equal(3);
  });

  it('should hold an outside-effect job in a fork without running it', async () => {
    // Arrange
    const held = job({ outsideEffect: true });
    const store = new ScriptedStore([[held]]);
    const handler = new Handler('work');
    const subject = new JobRunner(store, [handler], new RetryPolicy(), true, options);

    // Act
    const actual = await subject.drain();

    // Assert
    actual.held.should.equal(1);
    handler.seen.should.deepEqual([]);
    store.events.should.deepEqual([`hold:${held.id}`]);
  });

  it('should still run an internal job in a fork', async () => {
    // Arrange
    const store = new ScriptedStore([[job()]]);
    const subject = new JobRunner(store, [new Handler('work')], new RetryPolicy(), true, options);

    // Act
    const actual = await subject.drain();

    // Assert
    actual.done.should.equal(1);
  });

  it('should fail a job whose kind has no handler', async () => {
    // Arrange
    const orphan = job({ kind: 'unknown' });
    const store = new ScriptedStore([[orphan]]);
    const subject = new JobRunner(store, [new Handler('work')], new RetryPolicy(), false, options);

    // Act
    const actual = await subject.drain();

    // Assert
    actual.failed.should.equal(1);
    store.events.should.deepEqual([`fail:${orphan.id}:no handler for job kind unknown`]);
  });

  it('should retry a failing job with the policy delay', async () => {
    // Arrange
    const flaky = job({ attempts: 2 });
    const store = new ScriptedStore([[flaky]]);
    const handler = new Handler('work', () => {
      throw new Error('provider down');
    });
    const subject = new JobRunner(store, [handler], new RetryPolicy(), false, options);

    // Act
    const actual = await subject.drain();

    // Assert
    actual.retried.should.equal(1);
    store.events.should.deepEqual([`retry:${flaky.id}:60:provider down`]);
  });

  it('should fail a job for good once its attempts are used up', async () => {
    // Arrange
    const spent = job({ attempts: 5 });
    const store = new ScriptedStore([[spent]]);
    const handler = new Handler('work', () => {
      throw 'plain failure';
    });
    const subject = new JobRunner(store, [handler], new RetryPolicy(5), false);

    // Act
    const actual = await subject.drain();

    // Assert
    actual.failed.should.equal(1);
    store.events.should.deepEqual([`fail:${spent.id}:plain failure`]);
  });
});
