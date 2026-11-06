import { describe, it } from 'bun:test';
import 'should';
import { z } from 'zod';
import type { ICacheStore } from '../../../src/lib/cache/interfaces';
import { CacheService } from '../../../src/lib/cache/service';

class MemoryCacheStore implements ICacheStore {
  readonly entries = new Map<string, { value: unknown; ttlSeconds: number }>();

  async get(key: string): Promise<unknown> {
    return this.entries.get(key)?.value;
  }

  async set(key: string, value: unknown, ttlSeconds: number): Promise<void> {
    this.entries.set(key, { value, ttlSeconds });
  }

  async delete(key: string): Promise<void> {
    this.entries.delete(key);
  }
}

const Counter = z.object({ count: z.number() });

describe('CacheService', () => {
  it('should return a cached value without computing', async () => {
    // Arrange
    const store = new MemoryCacheStore();
    await store.set('counter', { count: 1 }, 60);
    const subject = new CacheService(store);
    let computed = 0;

    // Act
    const actual = await subject.remember('counter', 60, Counter, async () => ({ count: ++computed }));

    // Assert
    actual.should.deepEqual({ count: 1 });
    computed.should.equal(0);
  });

  it('should compute and store a missing value with its time to live', async () => {
    // Arrange
    const store = new MemoryCacheStore();
    const subject = new CacheService(store);

    // Act
    const actual = await subject.remember('counter', 30, Counter, async () => ({ count: 7 }));

    // Assert
    actual.should.deepEqual({ count: 7 });
    (store.entries.get('counter') as { value: unknown; ttlSeconds: number }).should.deepEqual({
      value: { count: 7 },
      ttlSeconds: 30,
    });
  });

  it('should recompute when the cached value no longer matches the schema', async () => {
    // Arrange
    const store = new MemoryCacheStore();
    await store.set('counter', { count: 'stale shape' }, 60);
    const subject = new CacheService(store);

    // Act
    const actual = await subject.remember('counter', 60, Counter, async () => ({ count: 2 }));

    // Assert
    actual.should.deepEqual({ count: 2 });
  });

  it('should forget a key', async () => {
    // Arrange
    const store = new MemoryCacheStore();
    await store.set('counter', { count: 1 }, 60);
    const subject = new CacheService(store);

    // Act
    await subject.forget('counter');

    // Assert
    store.entries.has('counter').should.be.false();
  });
});
