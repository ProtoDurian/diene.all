import type { ConfigRecord } from './merge.js';

type EnvRecord = Record<string, string | undefined>;

interface ConfigSource {
  base(): Promise<ConfigRecord>;
  overlay(landscape: string): Promise<ConfigRecord>;
  buildTimeEnv(): Promise<EnvRecord>;
  runtimeEnv(): Promise<EnvRecord>;
}

export type { ConfigSource, EnvRecord };
