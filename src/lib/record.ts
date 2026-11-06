class RecordTools {
  // biome-ignore lint/complexity/noUselessConstructor: Bun coverage counts an implicit constructor as an uncovered function
  constructor() {}

  isRecord(value: unknown): value is Record<string, unknown> {
    return typeof value === 'object' && value !== null && !Array.isArray(value);
  }

  stableConfig(value: unknown): unknown {
    return this.normalize(value, new WeakSet<object>());
  }

  private normalize(value: unknown, seen: WeakSet<object>): unknown {
    if (!Array.isArray(value) && !this.isPlainObject(value)) return value;
    if (seen.has(value)) throw new TypeError('stableConfig cannot process a circular structure');
    seen.add(value);
    const normalized = Array.isArray(value)
      ? value.map(item => this.normalize(item, seen))
      : Object.fromEntries(
          Object.keys(value)
            .sort()
            .map(key => [key, this.normalize(value[key], seen)]),
        );
    seen.delete(value);
    return normalized;
  }

  private isPlainObject(value: unknown): value is Record<string, unknown> {
    if (!this.isRecord(value)) return false;
    const prototype = Object.getPrototypeOf(value);
    return prototype === Object.prototype || prototype === null;
  }
}

export { RecordTools };
