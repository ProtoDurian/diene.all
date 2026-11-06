import { relative, resolve, sep } from 'node:path/posix';
import { portError, type VfsError, validateVfsPath } from '@atomicloud/diene.interfaces';
import { Err, type Result } from '@atomicloud/diene.result';

class SafePath {
  // biome-ignore lint/complexity/noUselessConstructor: Bun coverage counts an implicit constructor as an uncovered function
  constructor() {}

  safeJoin(root: string, ...segments: readonly string[]): Result<string, VfsError> {
    return validateVfsPath(root, 'safeJoin').andThen(base => {
      const candidate = resolve(base, ...segments);
      const fromRoot = relative(base, candidate);
      if (this.climbsAboveStart(segments) || fromRoot === '..' || fromRoot.startsWith('../')) {
        return Err(portError('vfs', 'invalid-input', 'safeJoin', 'path must remain beneath root', { root, segments }));
      }
      return validateVfsPath(candidate, 'safeJoin');
    });
  }

  // resolve() clamps '..' at '/', so a traversal under root '/' must be caught before it.
  private climbsAboveStart(segments: readonly string[]): boolean {
    let depth = 0;
    for (const segment of segments) {
      if (segment.startsWith(sep)) depth = 0;
      for (const part of segment.split(sep)) {
        if (part === '..') depth -= 1;
        else if (part !== '' && part !== '.') depth += 1;
        if (depth < 0) return true;
      }
    }
    return false;
  }
}

export { SafePath };
