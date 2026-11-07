import type { Result } from '@atomicloud/diene.result';
import { PortError, type VfsError } from './error.js';
import { type Checked, PortPolicy } from './validation.js';

type VfsEntryKind = 'directory' | 'file';

interface VfsEntry {
  readonly name: string;
  readonly kind: VfsEntryKind;
}

interface VfsStat {
  readonly kind: VfsEntryKind;
  readonly size: number;
}

interface CreateDirectoryOptions {
  readonly recursive?: boolean;
}

interface RemoveOptions {
  readonly recursive?: boolean;
}

interface VirtualFileSystem {
  readFile(path: string): Result<Uint8Array, VfsError>;
  writeFile(path: string, contents: Uint8Array): Result<void, VfsError>;
  exists(path: string): Result<boolean, VfsError>;
  stat(path: string): Result<VfsStat, VfsError>;
  list(path: string): Result<readonly VfsEntry[], VfsError>;
  createDirectory(path: string, options?: CreateDirectoryOptions): Result<void, VfsError>;
  remove(path: string, options?: RemoveOptions): Result<void, VfsError>;
}

class VfsPolicy extends PortPolicy {
  // biome-ignore lint/complexity/noUselessConstructor: Bun counts an implicit constructor as an uncovered function
  constructor() {
    super();
  }

  checkPath(path: string, operation: string): Checked<string, VfsError> {
    if (typeof path !== 'string' || path === '' || path.includes('\0')) {
      return this.invalid(operation, 'path', 'VFS path must be a non-empty NUL-free string');
    }
    if (!path.startsWith('/')) {
      return this.invalid(operation, 'path', 'VFS path must be absolute');
    }
    if (path !== '/' && (path.endsWith('/') || path.includes('//'))) {
      return this.invalid(operation, 'path', 'VFS path must be canonical');
    }
    if (path.split('/').some(segment => segment === '.' || segment === '..')) {
      return this.invalid(operation, 'path', 'VFS path must not contain dot segments');
    }
    return this.accept(path);
  }

  checkContents(contents: Uint8Array): Checked<Uint8Array, VfsError> {
    if (!(contents instanceof Uint8Array)) {
      return this.invalid('writeFile', 'contents', 'VFS file contents must be Uint8Array bytes');
    }
    return this.accept(new Uint8Array(contents));
  }

  checkRecursiveOptions(
    options: CreateDirectoryOptions | RemoveOptions | undefined,
    operation: 'createDirectory' | 'remove',
  ): Checked<Required<CreateDirectoryOptions>, VfsError> {
    if (options === undefined) return this.accept(Object.freeze({ recursive: false }));
    if (
      typeof options !== 'object' ||
      options === null ||
      Array.isArray(options) ||
      ![Object.prototype, null].includes(Object.getPrototypeOf(options))
    ) {
      return this.invalid(operation, 'options', 'VFS options must be an object');
    }
    if (options.recursive !== undefined && typeof options.recursive !== 'boolean') {
      return this.invalid(operation, 'recursive', 'recursive must be a boolean');
    }
    return this.accept(Object.freeze({ recursive: options.recursive ?? false }));
  }

  checkCreateDirectoryOptions(
    options: CreateDirectoryOptions | undefined,
  ): Checked<Required<CreateDirectoryOptions>, VfsError> {
    return this.checkRecursiveOptions(options, 'createDirectory');
  }

  checkRemoveOptions(options: RemoveOptions | undefined): Checked<Required<RemoveOptions>, VfsError> {
    return this.checkRecursiveOptions(options, 'remove');
  }

  validatePath(path: string, operation: string): Result<string, VfsError> {
    return this.toResult(this.checkPath(path, operation));
  }

  validateContents(contents: Uint8Array): Result<Uint8Array, VfsError> {
    return this.toResult(this.checkContents(contents));
  }

  validateRecursiveOptions(
    options: CreateDirectoryOptions | RemoveOptions | undefined,
    operation: 'createDirectory' | 'remove',
  ): Result<Required<CreateDirectoryOptions>, VfsError> {
    return this.toResult(this.checkRecursiveOptions(options, operation));
  }

  validateCreateDirectoryOptions(
    options: CreateDirectoryOptions | undefined,
  ): Result<Required<CreateDirectoryOptions>, VfsError> {
    return this.toResult(this.checkCreateDirectoryOptions(options));
  }

  validateRemoveOptions(options: RemoveOptions | undefined): Result<Required<RemoveOptions>, VfsError> {
    return this.toResult(this.checkRemoveOptions(options));
  }

  private invalid(operation: string, field: string, message: string): Checked<never, VfsError> {
    return this.reject(new PortError('vfs', 'invalid-input', operation, message, { field }));
  }
}

export type { CreateDirectoryOptions, RemoveOptions, VfsEntry, VfsEntryKind, VfsStat, VirtualFileSystem };
export { VfsPolicy };
