import { afterAll, beforeAll, describe, it } from 'bun:test';
import 'should';
import { PgDatabase } from '../../../src/adapters/db/database';
import { PostgresFixture } from '../../support/postgres';

describe('Tenant row-level security (Testcontainers Postgres)', () => {
  let postgres: PostgresFixture;
  let db: PgDatabase;
  let tenantA: string;
  let tenantB: string;
  let noteA: string;

  beforeAll(async () => {
    postgres = await PostgresFixture.start();
    db = new PgDatabase({ connectionString: postgres.connectionString });
    tenantA = await postgres.createTenant('tenant-a');
    tenantB = await postgres.createTenant('tenant-b');
    const [row] = await db.withTenant(tenantA, sql =>
      sql.query<{ id: string }>("INSERT INTO notes (title, body) VALUES ('secret', 'only for A') RETURNING id"),
    );
    noteA = (row as { id: string }).id;
    await db.withTenant(tenantA, async sql => {
      await sql.query("INSERT INTO jobs (kind, payload) VALUES ('work', '{}')");
      await sql.query("INSERT INTO cache_entries (key, value, expires_at) VALUES ('k', '1', now() + interval '1 hour')");
    });
  }, 120_000);

  afterAll(async () => {
    await db?.close();
    await postgres?.stop();
  }, 60_000);

  it('should let a tenant read its own rows', async () => {
    // Act
    const actual = await db.withTenant(tenantA, sql => sql.query('SELECT id FROM notes'));

    // Assert
    actual.should.have.length(1);
  });

  it.each(['notes', 'jobs', 'cache_entries'])('should hide %s rows from another tenant', async table => {
    // Act
    const actual = await db.withTenant(tenantB, sql => sql.query(`SELECT * FROM ${table}`));

    // Assert
    actual.should.have.length(0);
  });

  it('should show another tenant nothing of the tenants table but its own row', async () => {
    // Act
    const actual = await db.withTenant(tenantB, sql => sql.query<{ id: string }>('SELECT id FROM tenants'));

    // Assert
    actual.map(row => row.id).should.deepEqual([tenantB]);
  });

  it('should not let another tenant update or delete the rows', async () => {
    // Act
    const updated = await db.withTenant(tenantB, sql =>
      sql.query("UPDATE notes SET title = 'stolen' WHERE id = $1 RETURNING id", [noteA]),
    );
    const deleted = await db.withTenant(tenantB, sql => sql.query('DELETE FROM notes WHERE id = $1 RETURNING id', [noteA]));
    const [kept] = await db.withTenant(tenantA, sql =>
      sql.query<{ title: string }>('SELECT title FROM notes WHERE id = $1', [noteA]),
    );

    // Assert
    updated.should.have.length(0);
    deleted.should.have.length(0);
    (kept as { title: string }).title.should.equal('secret');
  });

  it('should refuse a row written into another tenant', async () => {
    // Act
    const attempt = db.withTenant(tenantB, sql =>
      sql.query("INSERT INTO notes (tenant_id, title, body) VALUES ($1, 'planted', 'x')", [tenantA]),
    );

    // Assert
    await attempt.should.be.rejectedWith(/row-level security/);
  });

  it('should see no tenant rows at all without a tenant', async () => {
    // Act
    const actual = await postgres.admin(async client => {
      await client.query('BEGIN');
      await client.query('SET LOCAL ROLE app_runtime');
      const result = await client.query('SELECT id FROM notes');
      await client.query('ROLLBACK');
      return result.rows;
    });

    // Assert
    actual.should.have.length(0);
  });

  it('should keep the runtime role free of superuser and BYPASSRLS', async () => {
    // Act
    const actual = await postgres.admin(async client => {
      const result = await client.query(
        "SELECT rolname, rolsuper, rolbypassrls FROM pg_roles WHERE rolname IN ('app_runtime', 'app_system') ORDER BY rolname",
      );
      return result.rows;
    });

    // Assert
    actual.should.deepEqual([
      { rolname: 'app_runtime', rolsuper: false, rolbypassrls: false },
      { rolname: 'app_system', rolsuper: false, rolbypassrls: false },
    ]);
  });

  it('should force row-level security on every tenant-owned table', async () => {
    // Act
    const actual = await postgres.admin(async client => {
      const result = await client.query(
        "SELECT relname, relrowsecurity, relforcerowsecurity FROM pg_class WHERE relname IN ('tenants', 'notes', 'jobs', 'cache_entries') ORDER BY relname",
      );
      return result.rows;
    });

    // Assert
    actual.should.deepEqual(
      ['cache_entries', 'jobs', 'notes', 'tenants'].map(relname => ({ relname, relrowsecurity: true, relforcerowsecurity: true })),
    );
  });
});
