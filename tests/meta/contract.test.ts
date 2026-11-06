import { mkdtemp, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { stringify } from 'yaml';
import { YamlConfigSource } from '../../src/adapters/yaml-source.js';
import { InMemoryConfigSource, type InMemoryTiers } from '../../src/test-helper/index.js';
import { runContract, type SourceFactory } from './contract/behaviours.js';

class YamlFactory implements SourceFactory {
  readonly name = 'YamlConfigSource (real files)';
  private readonly dirs: string[] = [];

  async create(tiers: InMemoryTiers): Promise<YamlConfigSource> {
    const dir = await mkdtemp(join(tmpdir(), 'diene-config-meta-'));
    this.dirs.push(dir);
    await writeFile(join(dir, 'config.yaml'), stringify(tiers.base ?? {}));
    for (const [landscape, overlay] of Object.entries(tiers.overlays ?? {})) {
      await writeFile(join(dir, `${landscape}.config.yaml`), stringify(overlay));
    }
    return new YamlConfigSource({ dir, env: tiers.runtimeEnv ?? {}, buildTimeEnv: tiers.buildTimeEnv ?? {} });
  }

  async dispose(): Promise<void> {
    await Promise.all(this.dirs.map(dir => rm(dir, { recursive: true, force: true })));
  }
}

class InMemoryFactory implements SourceFactory {
  readonly name = 'InMemoryConfigSource (fake)';

  async create(tiers: InMemoryTiers): Promise<InMemoryConfigSource> {
    return new InMemoryConfigSource(tiers);
  }

  async dispose(): Promise<void> {}
}

runContract(new YamlFactory());
runContract(new InMemoryFactory());
