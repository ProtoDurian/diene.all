import type { ConfigRecord } from '../../../src/lib/merge.js';
import type { ConfigSource, EnvRecord } from '../../../src/lib/source.js';

interface FakeTiers {
  base?: ConfigRecord;
  overlays?: Record<string, ConfigRecord>;
  buildTimeEnv?: EnvRecord;
  runtimeEnv?: EnvRecord;
  failBase?: Error;
}

class FakeSource implements ConfigSource {
  readonly overlayCalls: string[] = [];

  constructor(private readonly tiers: FakeTiers) {}

  async base(): Promise<ConfigRecord> {
    if (this.tiers.failBase) throw this.tiers.failBase;
    return this.tiers.base ?? {};
  }

  async overlay(landscape: string): Promise<ConfigRecord> {
    this.overlayCalls.push(landscape);
    return this.tiers.overlays?.[landscape] ?? {};
  }

  async buildTimeEnv(): Promise<EnvRecord> {
    return this.tiers.buildTimeEnv ?? {};
  }

  async runtimeEnv(): Promise<EnvRecord> {
    return this.tiers.runtimeEnv ?? {};
  }
}

export type { FakeTiers };
export { FakeSource };
