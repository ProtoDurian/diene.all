import { Err, Ok, type Result } from '@atomicloud/diene.result';

class NamespacedKeyValidationError extends Error {
  constructor(
    readonly field: 'namespace' | 'key',
    readonly reason: string,
  ) {
    super(`${field} ${reason}`);
    this.name = 'NamespacedKeyValidationError';
  }
}

class Slugger {
  // biome-ignore lint/complexity/noUselessConstructor: Bun coverage counts an implicit constructor as an uncovered function
  constructor() {}

  slugify(input: string): string {
    return input
      .normalize('NFKD')
      .replace(/[̀-ͯ]/g, '')
      .toLowerCase()
      .trim()
      .replace(/[^a-z0-9]+/g, '-')
      .replace(/^-+|-+$/g, '');
  }

  namespacedKey(namespace: string, key: string): Result<string, NamespacedKeyValidationError> {
    const ns = this.slugify(namespace);
    if (ns === '') return Err(new NamespacedKeyValidationError('namespace', 'must not be empty'));
    const k = this.slugify(key);
    if (k === '') return Err(new NamespacedKeyValidationError('key', 'must not be empty'));
    return Ok(`${ns}:${k}`);
  }
}

export { NamespacedKeyValidationError, Slugger };
