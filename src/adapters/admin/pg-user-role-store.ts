import { Err, Ok, Res, type Result } from '@atomicloud/diene.result';
import { Client } from 'pg';
import type { UserRoleStore } from '../../lib/admin/interfaces';
import type { AdminError, UserRole } from '../../lib/admin/structures';

// Runs as the database owner, like migrate: the auth tables have no row-level security.
export class PgUserRoleStore implements UserRoleStore {
  constructor(private readonly connectionString: string) {}

  find(email: string): Result<UserRole | undefined, AdminError> {
    return this.run(async client => {
      const result = await client.query<{ id: string; email: string; role: string | null }>(
        'SELECT "id", "email", "role" FROM "user" WHERE lower("email") = $1',
        [email],
      );
      const row = result.rows[0];
      if (!row) return undefined;
      return row.role === null ? { id: row.id, email: row.email } : { id: row.id, email: row.email, role: row.role };
    });
  }

  setRole(userId: string, role: string): Result<void, AdminError> {
    return this.run(async client => {
      await client.query('UPDATE "user" SET "role" = $1, "updatedAt" = now() WHERE "id" = $2', [role, userId]);
    });
  }

  private run<T>(work: (client: Client) => Promise<T>): Result<T, AdminError> {
    return Res.async(async () => {
      const client = new Client({ connectionString: this.connectionString });
      try {
        await client.connect();
        return Ok<T, AdminError>(await work(client));
      } catch (error) {
        return Err<T, AdminError>({ kind: 'store_failed', message: (error as Error).message });
      } finally {
        await client.end();
      }
    });
  }
}
