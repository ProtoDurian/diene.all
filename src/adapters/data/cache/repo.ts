import type { IDatabase, ISqlExecutor } from '../../../lib/db/interfaces';
import type { ICacheStore } from '../../../lib/cache/interfaces';

export class PgCacheStore implements ICacheStore {
  constructor(private readonly sql: ISqlExecutor) {}

  async get(key: string): Promise<unknown> {
    const rows = await this.sql.query<{ value: unknown }>(
      'SELECT value FROM cache_entries WHERE key = $1 AND expires_at > now()',
      [key],
    );
    return rows[0]?.value;
  }

  async set(key: string, value: unknown, ttlSeconds: number): Promise<void> {
    await this.sql.query(
      `INSERT INTO cache_entries (key, value, expires_at) VALUES ($1, $2, now() + make_interval(secs => $3))
       ON CONFLICT (tenant_id, key) DO UPDATE SET value = EXCLUDED.value, expires_at = EXCLUDED.expires_at`,
      [key, JSON.stringify(value), ttlSeconds],
    );
  }

  async delete(key: string): Promise<void> {
    await this.sql.query('DELETE FROM cache_entries WHERE key = $1', [key]);
  }
}

export class PgCachePurger {
  constructor(private readonly db: IDatabase) {}

  purgeExpired(): Promise<number> {
    return this.db.withSystem(async sql => {
      const rows = await sql.query('DELETE FROM cache_entries WHERE expires_at <= now() RETURNING key');
      return rows.length;
    });
  }
}
