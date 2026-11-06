import type { EnvRecord } from './source.js';

class BuildTimeValueMapper {
  // biome-ignore lint/complexity/noUselessConstructor: Bun coverage counts an implicit constructor as an uncovered function
  constructor() {}

  // Blank values are unset, so a secret that only exists at runtime is never inlined.
  map(env: EnvRecord, prefix: string): Record<string, string> {
    return Object.fromEntries(
      Object.entries(env).filter(
        (entry): entry is [string, string] => entry[0].startsWith(prefix) && entry[1] !== undefined && entry[1] !== '',
      ),
    );
  }
}

export { BuildTimeValueMapper };
