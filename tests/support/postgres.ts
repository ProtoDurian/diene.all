import { resolve } from 'node:path';
import { Client } from 'pg';
import { GenericContainer, type StartedTestContainer, Wait } from 'testcontainers';
import { PgMigrator } from '../../src/adapters/db/migrator';

const POSTGRES_IMAGE = 'postgres:17.11-alpine';
export const MIGRATIONS_DIR = resolve(import.meta.dir, '../../db/migrations');

export class PostgresFixture {
  private constructor(
    private readonly container: StartedTestContainer,
    readonly connectionString: string,
  ) {}

  static async start(options: { migrate?: boolean } = {}): Promise<PostgresFixture> {
    const password = crypto.randomUUID();
    const container = await new GenericContainer(POSTGRES_IMAGE)
      .withEnvironment({ POSTGRES_PASSWORD: password, POSTGRES_DB: 'app' })
      .withExposedPorts(5432)
      .withWaitStrategy(Wait.forLogMessage(/database system is ready to accept connections/, 2))
      .start();
    const url = `postgres://postgres:${password}@${container.getHost()}:${container.getMappedPort(5432)}/app`;
    const fixture = new PostgresFixture(container, url);
    if (options.migrate !== false) await new PgMigrator({ connectionString: url }).migrate(MIGRATIONS_DIR);
    return fixture;
  }

  async admin<T>(work: (client: Client) => Promise<T>): Promise<T> {
    const client = new Client({ connectionString: this.connectionString });
    await client.connect();
    try {
      return await work(client);
    } finally {
      await client.end();
    }
  }

  async createTenant(slug: string, status: 'pending' | 'approved' | 'suspended' = 'approved'): Promise<string> {
    const id = crypto.randomUUID();
    await this.admin(client =>
      client.query(
        "INSERT INTO tenants (id, slug, status, approved_at) VALUES ($1, $2, $3, CASE WHEN $3 = 'approved' THEN now() END)",
        [id, slug, status],
      ),
    );
    return id;
  }

  async markFork(source = 'production'): Promise<void> {
    await this.admin(client =>
      client.query('UPDATE fork_meta SET is_fork = true, source = $1, forked_at = now()', [source]),
    );
  }

  async stop(): Promise<void> {
    await this.container.stop();
  }
}
