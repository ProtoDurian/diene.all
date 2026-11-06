import { readFile } from 'node:fs/promises';
import { join } from 'node:path';
import { isRecord } from '@atomicloud/diene.core-utils';
import { parse as parseYaml } from 'yaml';
import type { ConfigRecord } from '../lib/merge.js';
import type { ConfigSource, EnvRecord } from '../lib/source.js';

class YamlConfigSourceError extends Error {
  constructor(message: string, options?: ErrorOptions) {
    super(message, options);
    this.name = 'YamlConfigSourceError';
  }
}

interface YamlConfigSourceOptions {
  dir: string;
  baseFile?: string;
  overlayFile?: (landscape: string) => string;
  env?: EnvRecord;
  buildTimeEnv?: EnvRecord;
}

class YamlConfigSource implements ConfigSource {
  private readonly dir: string;
  private readonly baseFile: string;
  private readonly overlayFile: (landscape: string) => string;
  private readonly env: EnvRecord;
  private readonly buildTime: EnvRecord;

  constructor(options: YamlConfigSourceOptions) {
    this.dir = options.dir;
    this.baseFile = options.baseFile ?? 'config.yaml';
    this.overlayFile = options.overlayFile ?? (landscape => `${landscape}.config.yaml`);
    this.env = options.env ?? process.env;
    this.buildTime = options.buildTimeEnv ?? {};
  }

  base(): Promise<ConfigRecord> {
    return this.read(join(this.dir, this.baseFile), true);
  }

  overlay(landscape: string): Promise<ConfigRecord> {
    return this.read(join(this.dir, this.overlayFile(landscape)), false);
  }

  async buildTimeEnv(): Promise<EnvRecord> {
    return this.buildTime;
  }

  async runtimeEnv(): Promise<EnvRecord> {
    return this.env;
  }

  private async read(path: string, required: boolean): Promise<ConfigRecord> {
    let text: string;
    try {
      text = await readFile(path, 'utf8');
    } catch (error) {
      if (!required && (error as { code?: string }).code === 'ENOENT') return {};
      throw error;
    }
    const parsed = this.parse(text, path);
    if (parsed === null || parsed === undefined) return {};
    if (!isRecord(parsed)) throw new YamlConfigSourceError(`config file is not a mapping: ${path}`);
    return parsed;
  }

  private parse(text: string, path: string): unknown {
    try {
      return parseYaml(text);
    } catch (error) {
      throw new YamlConfigSourceError(`${path}: ${(error as Error).message}`, { cause: error });
    }
  }
}

export type { YamlConfigSourceOptions };
export { YamlConfigSource, YamlConfigSourceError };
