class ConcurrencyMapper {
  // biome-ignore lint/complexity/noUselessConstructor: Bun coverage counts an implicit constructor as an uncovered function
  constructor() {}

  async mapWithConcurrency<T, R>(
    items: readonly T[],
    concurrency: number,
    mapper: (item: T, index: number) => Promise<R> | R,
  ): Promise<R[]> {
    if (!Number.isInteger(concurrency) || concurrency < 1) {
      throw new RangeError(`concurrency must be a positive integer; received ${concurrency}`);
    }

    const results = new Array<R>(items.length);
    let next = 0;
    let failed = false;
    const worker = async (): Promise<void> => {
      while (!failed && next < items.length) {
        const current = next;
        next += 1;
        try {
          results[current] = await mapper(items[current] as T, current);
        } catch (error) {
          failed = true;
          throw error;
        }
      }
    };

    await Promise.all(Array.from({ length: Math.min(concurrency, items.length) }, worker));
    return results;
  }
}

export { ConcurrencyMapper };
