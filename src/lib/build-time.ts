import { EnvKeyMatcher } from './coerce.js';
import { NESTING_SEPARATOR } from './env.js';
import type { EnvRecord } from './source.js';

class BuildTimeValueMapper {
  constructor(private readonly matcher: EnvKeyMatcher = new EnvKeyMatcher()) {}

  // Only client values may be inlined, and the client BUILD subtree holds build-step secrets.
  map(env: EnvRecord, prefix: string): Record<string, string> {
    return Object.fromEntries(
      Object.entries(env).filter(
        (entry): entry is [string, string] =>
          entry[1] !== undefined &&
          entry[1] !== '' &&
          entry[0].startsWith(prefix) &&
          this.inlineable(entry[0].slice(prefix.length)),
      ),
    );
  }

  private inlineable(name: string): boolean {
    const [scope, ...rest] = name.split(NESTING_SEPARATOR).map(segment => this.matcher.normalize(segment));
    return scope === 'client' && rest.length > 0 && !rest.includes('build');
  }
}

export { BuildTimeValueMapper };
