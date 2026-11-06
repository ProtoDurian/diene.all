import { readdir, readFile } from 'node:fs/promises';
import { join } from 'node:path';
import { Client } from 'pg';
import type { IMigrationLedger, IMigrationSession, IMigrationSource } from '../../lib/db/interfaces';
import { MigrationPlanner, MigrationService } from '../../lib/db/service';
import type { AppliedMigration, Migration, MigrationDrift } from '../../lib/db/structures';
import type { ConnectionSource } from './database';

const MIGRATION_FILE = /^(\d{4})_([a-z0-9_]+)\.sql$/;
const LEDGER_LOCK_KEY = 7_311_942_001;

export class MigrationFileError extends Error {
  constructor(readonly file: string) {
    super(`migration file ${file} must be named NNNN_lower_snake.sql`);
    this.name = 'MigrationFileError';
  }
}

export class MigrationDriftError extends Error {
  constructor(readonly drift: MigrationDrift) {
    super(`migration ${drift.version} (${drift.name}) cannot be applied: ${drift.kind}`);
    this.name = 'MigrationDriftError';
  }
}

export class FileMigrationSource implements IMigrationSource {
  constructor(private readonly directory: string) {}

  async list(): Promise<readonly Migration[]> {
    const files = (await readdir(this.directory)).filter(file => file.endsWith('.sql')).sort();
    return Promise.all(files.map(file => this.load(file)));
  }

  private async load(file: string): Promise<Migration> {
    const match = MIGRATION_FILE.exec(file);
    if (match === null) throw new MigrationFileError(file);
    const sql = await readFile(join(this.directory, file), 'utf8');
    const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(sql));
    const checksum = [...new Uint8Array(digest)].map(byte => byte.toString(16).padStart(2, '0')).join('');
    return { version: Number(match[1]), name: file.slice(0, -'.sql'.length), sql, checksum };
  }
}

class ClientMigrationSession implements IMigrationSession {
  constructor(private readonly client: Client) {}

  async applied(): Promise<readonly AppliedMigration[]> {
    const result = await this.client.query<AppliedMigration>(
      'SELECT version, name, checksum FROM schema_migrations ORDER BY version',
    );
    return result.rows;
  }

  async apply(migration: Migration): Promise<void> {
    await this.client.query('BEGIN');
    try {
      await this.client.query(migration.sql);
      await this.client.query('INSERT INTO schema_migrations (version, name, checksum) VALUES ($1, $2, $3)', [
        migration.version,
        migration.name,
        migration.checksum,
      ]);
      await this.client.query('COMMIT');
    } catch (error) {
      await this.client.query('ROLLBACK');
      throw error;
    }
  }
}

class PgMigrationLedger implements IMigrationLedger {
  constructor(private readonly source: ConnectionSource) {}

  async exclusive<T>(work: (session: IMigrationSession) => Promise<T>): Promise<T> {
    const client = new Client({ connectionString: this.source.connectionString });
    await client.connect();
    try {
      await client.query('SELECT pg_advisory_lock($1)', [LEDGER_LOCK_KEY]);
      await client.query(
        `CREATE TABLE IF NOT EXISTS schema_migrations (
          version integer PRIMARY KEY,
          name text NOT NULL,
          checksum text NOT NULL,
          applied_at timestamptz NOT NULL DEFAULT now()
        )`,
      );
      return await work(new ClientMigrationSession(client));
    } finally {
      await client.end();
    }
  }
}

/** Applies `db/migrations` in order; one advisory lock keeps concurrent runs from racing. */
export class PgMigrator {
  constructor(private readonly source: ConnectionSource) {}

  async migrate(directory: string): Promise<readonly string[]> {
    const service = new MigrationService(
      new FileMigrationSource(directory),
      new PgMigrationLedger(this.source),
      new MigrationPlanner(),
    );
    return service.migrate().match({
      ok: names => names,
      err: drift => {
        throw new MigrationDriftError(drift);
      },
    });
  }
}
