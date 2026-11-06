import { isRecord } from '@atomicloud/diene.core-utils';
import type { ConfigRecord } from '../lib/merge.js';
import type { ConfigSource, EnvRecord } from '../lib/source.js';

interface InMemoryTiers {
  base?: ConfigRecord;
  overlays?: Record<string, ConfigRecord>;
  buildTimeEnv?: EnvRecord;
  runtimeEnv?: EnvRecord;
}

class InMemoryConfigSource implements ConfigSource {
  constructor(private readonly tiers: InMemoryTiers = {}) {}

  async base(): Promise<ConfigRecord> {
    return this.tiers.base ?? {};
  }

  async overlay(landscape: string): Promise<ConfigRecord> {
    return this.tiers.overlays?.[landscape] ?? {};
  }

  async buildTimeEnv(): Promise<EnvRecord> {
    return this.tiers.buildTimeEnv ?? {};
  }

  async runtimeEnv(): Promise<EnvRecord> {
    return this.tiers.runtimeEnv ?? {};
  }
}

class LandscapeConfigSource extends InMemoryConfigSource {
  constructor(landscape: string, tiers: InMemoryTiers = {}) {
    const app = isRecord(tiers.base?.app) ? tiers.base.app : {};
    super({ ...tiers, base: { ...tiers.base, app: { ...app, landscape } } });
  }
}

export type { InMemoryTiers };
export { InMemoryConfigSource, LandscapeConfigSource };
