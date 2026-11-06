import { Pool, type PoolClient } from 'pg';
import type { IDatabase, ISqlExecutor } from '../../lib/db/interfaces';
import type { SqlRow } from '../../lib/db/structures';

/** The Hyperdrive binding's shape; Worker code passes `env.HYPERDRIVE` and nothing else. */
export interface ConnectionSource {
  readonly connectionString: string;
}

class ClientExecutor implements ISqlExecutor {
  constructor(private readonly client: PoolClient) {}

  async query<R extends SqlRow = SqlRow>(text: string, params: readonly unknown[] = []): Promise<readonly R[]> {
    const result = await this.client.query<R>(text, [...params]);
    return result.rows;
  }
}

export class PgDatabase implements IDatabase {
  readonly pool: Pool;

  constructor(source: ConnectionSource, maxConnections = 5) {
    this.pool = new Pool({ connectionString: source.connectionString, max: maxConnections });
  }

  withTenant<T>(tenantId: string, work: (sql: ISqlExecutor) => Promise<T>): Promise<T> {
    return this.transaction(async client => {
      await client.query('SET LOCAL ROLE app_runtime');
      await client.query("SELECT set_config('app.tenant_id', $1, true)", [tenantId]);
      return work(new ClientExecutor(client));
    });
  }

  withSystem<T>(work: (sql: ISqlExecutor) => Promise<T>): Promise<T> {
    return this.transaction(async client => {
      await client.query('SET LOCAL ROLE app_system');
      return work(new ClientExecutor(client));
    });
  }

  async close(): Promise<void> {
    await this.pool.end();
  }

  private async transaction<T>(work: (client: PoolClient) => Promise<T>): Promise<T> {
    const client = await this.pool.connect();
    let failed = false;
    try {
      await client.query('BEGIN');
      const result = await work(client);
      await client.query('COMMIT');
      return result;
    } catch (error) {
      failed = true;
      await client.query('ROLLBACK');
      throw error;
    } finally {
      client.release(failed);
    }
  }
}
