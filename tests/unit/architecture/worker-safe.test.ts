import { beforeAll, describe, it } from 'bun:test';
import { mkdir, mkdtemp, readdir, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import 'should';
import { REPOSITORY_ROOT, WorkerGraph, type WorkerModule } from '../../support/worker-graph';

const BUN_GLOBAL = /\bBun\s*\.|\bBun\s*\[/;
const BUN_MODULE = /^bun(?::|$)/;
const BUNDLED_BUN_IMPORT = /(?:from\s*|import\s*\(\s*|require\s*\(\s*)["']bun(?::[^"']*)?["']/;

describe('Worker code runs on workerd, not Bun', () => {
  let modules: readonly WorkerModule[];

  beforeAll(async () => {
    modules = await new WorkerGraph().modules();
  });

  it('should not use the Bun global in any module the Worker reaches', () => {
    // Act
    const actual = modules.filter(module => BUN_GLOBAL.test(module.code)).map(module => module.path);

    // Assert
    actual.should.deepEqual([]);
  });

  it('should not import a Bun module', () => {
    // Act
    const actual = modules
      .filter(module => module.packages.some(name => BUN_MODULE.test(name)))
      .map(module => module.path);

    // Assert
    actual.should.deepEqual([]);
  });

  it('should bundle with wrangler without any Bun import', async () => {
    // Arrange
    const outdir = await mkdtemp(join(tmpdir(), 'aseity-bundle-'));
    await mkdir(join(REPOSITORY_ROOT, 'dist/web'), { recursive: true });

    // Act
    const build = Bun.spawnSync(['wrangler', 'deploy', '--dry-run', '--outdir', outdir], {
      cwd: REPOSITORY_ROOT,
      env: { ...process.env, CI: '1', WRANGLER_SEND_METRICS: 'false' },
    });
    const files = (await readdir(outdir)).filter(file => file.endsWith('.js'));
    const bundles = await Promise.all(files.map(file => Bun.file(join(outdir, file)).text()));
    await rm(outdir, { recursive: true, force: true });

    // Assert
    build.exitCode.should.equal(0, build.stderr.toString());
    files.length.should.be.above(0);
    bundles.filter(bundle => BUNDLED_BUN_IMPORT.test(bundle)).should.have.length(0);
  }, 120_000);
});
