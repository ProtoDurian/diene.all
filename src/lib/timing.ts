class Timing {
  // biome-ignore lint/complexity/noUselessConstructor: Bun coverage counts an implicit constructor as an uncovered function
  constructor() {}

  sleep(seconds: number): Promise<void> {
    if (!Number.isFinite(seconds) || seconds < 0) {
      return Promise.reject(
        new RangeError(`sleep(seconds) requires a finite, non-negative number; received ${seconds}`),
      );
    }
    return new Promise<void>(resolve => {
      setTimeout(resolve, seconds * 1000);
    });
  }

  noop(): void {}
}

export { Timing };
