import type { z } from 'zod';
import type { ICacheStore } from './interfaces';

export class CacheService {
  constructor(private readonly store: ICacheStore) {}

  async remember<S extends z.ZodType>(
    key: string,
    ttlSeconds: number,
    schema: S,
    compute: () => Promise<z.output<S>>,
  ): Promise<z.output<S>> {
    const cached = schema.safeParse(await this.store.get(key));
    if (cached.success) return cached.data;
    const fresh = await compute();
    await this.store.set(key, fresh, ttlSeconds);
    return fresh;
  }

  forget(key: string): Promise<void> {
    return this.store.delete(key);
  }
}
