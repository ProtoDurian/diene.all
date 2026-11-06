import { existsSync } from 'node:fs';
import { dirname, relative, resolve } from 'node:path';

export const REPOSITORY_ROOT = resolve(import.meta.dir, '../..');
const WORKER_ENTRY = 'src/index.ts';

export interface WorkerModule {
  readonly path: string;
  readonly code: string;
  readonly packages: readonly string[];
}

export class WorkerGraph {
  private readonly transpiler = new Bun.Transpiler({ loader: 'ts' });

  constructor(private readonly root: string = REPOSITORY_ROOT) {}

  async modules(entry: string = WORKER_ENTRY): Promise<readonly WorkerModule[]> {
    const seen = new Map<string, WorkerModule>();
    const queue = [resolve(this.root, entry)];
    while (queue.length > 0) {
      const file = queue.pop() as string;
      const path = relative(this.root, file);
      if (seen.has(path)) continue;
      const code = this.transpiler.transformSync(await Bun.file(file).text());
      const imports = this.transpiler.scanImports(code).map(entry => entry.path);
      const packages = imports.filter(specifier => !specifier.startsWith('.'));
      seen.set(path, { path, code, packages });
      for (const specifier of imports.filter(specifier => specifier.startsWith('.'))) {
        queue.push(this.resolveLocal(dirname(file), specifier));
      }
    }
    return [...seen.values()].sort((left, right) => left.path.localeCompare(right.path));
  }

  private resolveLocal(from: string, specifier: string): string {
    const base = resolve(from, specifier);
    const candidate = [base, `${base}.ts`, `${base}/index.ts`].find(path => path.endsWith('.ts') && existsSync(path));
    if (candidate === undefined) throw new Error(`cannot resolve ${specifier} from ${from}`);
    return candidate;
  }
}
