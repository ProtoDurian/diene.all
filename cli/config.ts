import {
  type BlockShape,
  type Config,
  ConfigLoader,
  type ConfigRecord,
  ConfigRegistry,
  type ConfigSource,
  type EnvRecord,
} from '@atomicloud/diene.config';
import { z } from 'zod';

const required = z.string().min(1);

// Env overrides only reach keys the base already has, so every key is listed here.
const BASE: ConfigRecord = {
  database: {
    provider: 'local',
    url: '',
    neon: {
      apiKey: '',
      projectId: '',
      parentBranchId: '',
      databaseName: '',
      roleName: '',
      baseUrl: 'https://console.neon.tech/api/v2',
      pollIntervalMs: 2000,
      pollAttempts: 60,
    },
  },
  storage: { provider: 'copy', endpoint: '', region: 'us-east-1', bucket: '', accessKeyId: '', secretAccessKey: '' },
};

const MigrateDatabaseSchema = z.object({ url: required });

const ForkDatabaseSchema = z.discriminatedUnion('provider', [
  z.object({ provider: z.literal('local'), url: required }),
  z.object({
    provider: z.literal('neon'),
    neon: z.object({
      apiKey: required,
      projectId: required,
      parentBranchId: z.string(),
      databaseName: required,
      roleName: required,
      baseUrl: z.url(),
      pollIntervalMs: z.number().int().positive(),
      pollAttempts: z.number().int().positive(),
    }),
  }),
]);

const StorageSchema = z.object({
  provider: z.enum(['copy', 'tigris']),
  endpoint: z.url(),
  region: required,
  bucket: required,
  accessKeyId: required,
  secretAccessKey: required,
});

export class EnvConfigSource implements ConfigSource {
  constructor(private readonly env: EnvRecord) {}

  async base(): Promise<ConfigRecord> {
    return structuredClone(BASE);
  }

  async overlay(): Promise<ConfigRecord> {
    return {};
  }

  async buildTimeEnv(): Promise<EnvRecord> {
    return {};
  }

  async runtimeEnv(): Promise<EnvRecord> {
    return this.env;
  }
}

export class CliConfig {
  constructor(private readonly source: ConfigSource) {}

  migrate() {
    return this.load(ConfigRegistry.create().register('database', MigrateDatabaseSchema));
  }

  admin() {
    return this.migrate();
  }

  fork() {
    return this.load(
      ConfigRegistry.create().register('database', ForkDatabaseSchema).register('storage', StorageSchema),
    );
  }

  private load<S extends BlockShape>(registry: ConfigRegistry<S>): Promise<Config<S>> {
    return new ConfigLoader(this.source, registry, { prefix: 'ASEITY_' }).load();
  }
}
