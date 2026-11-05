export class NamespacedKeyValidationError extends Error {
  constructor(
    readonly field: 'namespace' | 'key',
    readonly reason: string,
  ) {
    super(`${field} ${reason}`);
    this.name = 'NamespacedKeyValidationError';
  }
}

export class KeyComposer {
  constructor(private readonly namespace: string) {}

  slugify(input: string): string {
    return input
      .normalize('NFKD')
      .replace(/[̀-ͯ]/g, '')
      .toLowerCase()
      .trim()
      .replace(/[^a-z0-9]+/g, '-')
      .replace(/^-+|-+$/g, '');
  }

  compose(key: string): string {
    const ns = this.slugify(this.namespace);
    const k = this.slugify(key);
    if (ns === '') throw new NamespacedKeyValidationError('namespace', 'must not be empty');
    if (k === '') throw new NamespacedKeyValidationError('key', 'must not be empty');
    return `${ns}:${k}`;
  }
}
