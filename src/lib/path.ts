import { relative, resolve } from 'node:path/posix';
import { portError, type VfsError, validateVfsPath } from '@atomicloud/diene.interfaces';
import { Err, type Result } from '@atomicloud/diene.result';

class SafePath {
  // biome-ignore lint/complexity/noUselessConstructor: Bun coverage counts an implicit constructor as an uncovered function
  constructor() {}

  safeJoin(root: string, ...segments: readonly string[]): Result<string, VfsError> {
    return validateVfsPath(root, 'safeJoin').andThen(base => {
      const candidate = resolve(base, ...segments);
      const fromRoot = relative(base, candidate);
      if (fromRoot === '..' || fromRoot.startsWith('../')) {
        return Err(portError('vfs', 'invalid-input', 'safeJoin', 'path must remain beneath root', { root, segments }));
      }
      return validateVfsPath(candidate, 'safeJoin');
    });
  }
}

export { SafePath };
