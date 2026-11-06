import type { Result } from '@atomicloud/diene.result';
import { Client } from 'pg';
import type { DatabaseBrancher } from '../../lib/fork/interfaces';
import type { ForkNaming } from '../../lib/fork/naming';
import type { DatabaseBranch, ForkError } from '../../lib/fork/structures';
import { ForkFailure, ProviderAttempt } from './attempt';

const DUPLICATE_DATABASE = '42P04';
const UNDEFINED_DATABASE = '3D000';
const OBJECT_IN_USE = '55006';

// Copies the source database on the same server with CREATE DATABASE ... TEMPLATE.
export class LocalPostgresBrancher implements DatabaseBrancher {
  constructor(
    private readonly sourceConnectionString: string,
    private readonly naming: ForkNaming,
  ) {}

  private readonly attempt = new ProviderAttempt('database');

  create(fork: string): Result<DatabaseBranch, ForkError> {
    return this.naming.databaseName(fork).andThen(database =>
      this.attempt.run(async () => {
        await this.admin(async client => {
          const target = client.escapeIdentifier(database);
          const source = client.escapeIdentifier(this.naming.sources.database);
          await client.query(`CREATE DATABASE ${target} TEMPLATE ${source}`).catch(error => {
            throw this.translate(error, DUPLICATE_DATABASE, { kind: 'already_exists', name: fork });
          });
        });
        return { name: database, connectionString: this.urlFor(database) };
      }),
    );
  }

  list(): Result<readonly string[], ForkError> {
    return this.attempt.run(() =>
      this.admin(async client => {
        const result = await client.query<{ datname: string }>('SELECT datname FROM pg_database ORDER BY datname');
        return result.rows.flatMap(row => this.naming.databaseFork(row.datname) ?? []);
      }),
    );
  }

  delete(fork: string): Result<void, ForkError> {
    return this.naming.databaseName(fork).andThen(database =>
      this.attempt.run(() =>
        this.admin(async client => {
          await client.query(`DROP DATABASE ${client.escapeIdentifier(database)} WITH (FORCE)`).catch(error => {
            throw this.translate(error, UNDEFINED_DATABASE, { kind: 'not_found', name: fork });
          });
        }),
      ),
    );
  }

  // A missing template also raises UNDEFINED_DATABASE, so each statement names the one code that means the fork.
  private translate(error: { code?: string; message: string }, forkCode: string, forkError: ForkError): Error {
    if (error.code === forkCode) return new ForkFailure(forkError);
    if (error.code === OBJECT_IN_USE) {
      return new Error(`${error.message}: stop every client of the source database (wrangler dev, psql) and retry`);
    }
    return new Error(error.message);
  }

  // CREATE DATABASE cannot run while connected to its template, so admin work uses the maintenance database.
  private async admin<T>(work: (client: Client) => Promise<T>): Promise<T> {
    const client = new Client({ connectionString: this.urlFor('postgres') });
    await client.connect();
    try {
      return await work(client);
    } finally {
      await client.end();
    }
  }

  private urlFor(database: string): string {
    const url = new URL(this.sourceConnectionString);
    url.pathname = `/${database}`;
    return url.toString();
  }
}
