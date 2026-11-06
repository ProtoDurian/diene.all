import { afterAll, beforeAll, describe, it } from 'bun:test';
import 'should';
import { PgDatabase } from '../../../src/adapters/db/database';
import { PostgresFixture } from '../../support/postgres';

describe('PgDatabase (Testcontainers Postgres)', () => {
  let postgres: PostgresFixture;
  let subject: PgDatabase;
  let tenant: string;

  beforeAll(async () => {
    postgres = await PostgresFixture.start();
    subject = new PgDatabase({ connectionString: postgres.connectionString });
    tenant = await postgres.createTenant('acme');
  }, 120_000);

  afterAll(async () => {
    await subject?.close();
    await postgres?.stop();
  }, 60_000);

  it('should run tenant work as the runtime role with the tenant setting applied', async () => {
    // Act
    const actual = await subject.withTenant(tenant, sql =>
      sql.query<{ role: string; tenant: string }>('SELECT current_user AS role, app_current_tenant()::text AS tenant'),
    );

    // Assert
    actual.should.deepEqual([{ role: 'app_runtime', tenant }]);
  });

  it('should run system work as the system role without a tenant', async () => {
    // Act
    const actual = await subject.withSystem(sql =>
      sql.query<{ role: string; tenant: string | null }>('SELECT current_user AS role, app_current_tenant() AS tenant'),
    );

    // Assert
    actual.should.deepEqual([{ role: 'app_system', tenant: null }]);
  });

  it('should not leak the tenant setting to the next transaction on a reused connection', async () => {
    // Arrange
    const single = new PgDatabase({ connectionString: postgres.connectionString }, 1);
    await single.withTenant(tenant, sql => sql.query('SELECT 1'));

    // Act
    const actual = await single.withSystem(sql =>
      sql.query<{ tenant: string | null }>('SELECT app_current_tenant() AS tenant'),
    );
    await single.close();

    // Assert
    actual.should.deepEqual([{ tenant: null }]);
  });

  it('should roll back the transaction when the work throws', async () => {
    // Arrange
    const failing = subject.withTenant(tenant, async sql => {
      await sql.query("INSERT INTO notes (title, body) VALUES ('lost', 'never committed')");
      throw new Error('boom');
    });

    // Act
    await failing.should.be.rejectedWith('boom');
    const actual = await subject.withTenant(tenant, sql => sql.query("SELECT id FROM notes WHERE title = 'lost'"));

    // Assert
    actual.should.have.length(0);
  });
});
