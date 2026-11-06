import { afterAll, beforeAll, describe, it } from 'bun:test';
import { mkdtemp, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import 'should';
import { FileMigrationSource, MigrationDriftError, MigrationFileError, PgMigrator } from '../../../src/adapters/db/migrator';
import { MIGRATIONS_DIR, PostgresFixture } from '../../support/postgres';

describe('PgMigrator (Testcontainers Postgres)', () => {
  let postgres: PostgresFixture;
  let scratch: string;

  beforeAll(async () => {
    postgres = await PostgresFixture.start({ migrate: false });
    scratch = await mkdtemp(join(tmpdir(), 'aseity-migrations-'));
  }, 120_000);

  afterAll(async () => {
    await rm(scratch, { recursive: true, force: true });
    await postgres?.stop();
  }, 60_000);

  it('should apply every core migration in order on an empty database', async () => {
    // Arrange
    const subject = new PgMigrator({ connectionString: postgres.connectionString });
    const expected = (await new FileMigrationSource(MIGRATIONS_DIR).list()).map(migration => migration.name);

    // Act
    const actual = await subject.migrate(MIGRATIONS_DIR);

    // Assert
    actual.should.deepEqual(expected);
    actual.slice(0, 2).should.deepEqual(['0001_roles', '0002_tenants']);
  });

  it('should apply nothing when the database is current', async () => {
    // Arrange
    const subject = new PgMigrator({ connectionString: postgres.connectionString });

    // Act
    const actual = await subject.migrate(MIGRATIONS_DIR);

    // Assert
    actual.should.deepEqual([]);
  });

  it('should serialise concurrent runs so each migration applies once', async () => {
    // Arrange
    const dir = join(scratch, 'concurrent');
    await rm(dir, { recursive: true, force: true });
    await Bun.write(join(dir, '0001_one.sql'), 'CREATE TABLE concurrent_one (id int);');
    const fresh = await PostgresFixture.start({ migrate: false });
    const left = new PgMigrator({ connectionString: fresh.connectionString });
    const right = new PgMigrator({ connectionString: fresh.connectionString });

    // Act
    const actual = await Promise.all([left.migrate(dir), right.migrate(dir)]);
    await fresh.stop();

    // Assert
    actual.flat().should.deepEqual(['0001_one']);
  }, 120_000);

  it('should refuse a migration whose applied file changed', async () => {
    // Arrange
    const dir = join(scratch, 'changed');
    await Bun.write(join(dir, '0001_one.sql'), 'CREATE TABLE changed_one (id int);');
    const fresh = await PostgresFixture.start({ migrate: false });
    const subject = new PgMigrator({ connectionString: fresh.connectionString });
    await subject.migrate(dir);
    await writeFile(join(dir, '0001_one.sql'), 'CREATE TABLE changed_one (id bigint);');

    // Act
    const actual = (await subject.migrate(dir).catch((error: unknown) => error)) as Error;

    // Assert
    actual.should.be.instanceOf(MigrationDriftError);
    (actual as MigrationDriftError).drift.should.deepEqual({ kind: 'changed', version: 1, name: '0001_one' });
    await fresh.stop();
  }, 120_000);

  it('should roll back a failing migration and leave it unrecorded', async () => {
    // Arrange
    const dir = join(scratch, 'failing');
    await Bun.write(join(dir, '0001_bad.sql'), 'CREATE TABLE bad_one (id int); SELECT no_such_function();');
    const fresh = await PostgresFixture.start({ migrate: false });
    const subject = new PgMigrator({ connectionString: fresh.connectionString });

    // Act
    await subject.migrate(dir).should.be.rejected();
    const actual = await fresh.admin(async client => {
      const tables = await client.query("SELECT to_regclass('bad_one') AS bad");
      const ledger = await client.query('SELECT version FROM schema_migrations');
      return { bad: tables.rows[0].bad, recorded: ledger.rowCount };
    });
    await fresh.stop();

    // Assert
    actual.should.deepEqual({ bad: null, recorded: 0 });
  }, 120_000);

  it('should reject a migration file with a malformed name', async () => {
    // Arrange
    const dir = join(scratch, 'malformed');
    await Bun.write(join(dir, '1_Bad Name.sql'), 'SELECT 1;');
    const subject = new FileMigrationSource(dir);

    // Act
    const actual = (await subject.list().catch((error: unknown) => error)) as Error;

    // Assert
    actual.should.be.instanceOf(MigrationFileError);
    (actual as MigrationFileError).file.should.equal('1_Bad Name.sql');
  });
});
