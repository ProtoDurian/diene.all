import { afterAll, beforeAll, describe, it } from 'bun:test';
import { expectErr, expectOk } from '@atomicloud/diene.result/test-helper';
import { Client } from 'pg';
import 'should';
import { LocalPostgresBrancher } from '../../../src/adapters/fork/local-postgres-brancher';
import { ForkNaming } from '../../../src/lib/fork/naming';
import { PostgresFixture } from '../../support/postgres';

describe('LocalPostgresBrancher (Testcontainers Postgres)', () => {
  let db: PostgresFixture;
  let subject: LocalPostgresBrancher;

  beforeAll(async () => {
    db = await PostgresFixture.start();
    const tenantId = await db.createTenant('acme');
    await db.admin(client =>
      client.query("INSERT INTO notes (tenant_id, title, body) VALUES ($1, 'hello', 'world')", [tenantId]),
    );
    subject = new LocalPostgresBrancher(
      db.connectionString,
      new ForkNaming({ database: 'app', bucket: 'files' }));
  }, 120_000);

  afterAll(async () => {
    await db.stop();
  });

  it('should copy the source database, rows included', async () => {
    // Act
    const branch = await expectOk(subject.create('demo'));

    // Assert
    branch.name.should.equal('app_fork_demo');
    branch.connectionString.should.endWith('/app_fork_demo');
    const client = new Client({ connectionString: branch.connectionString });
    await client.connect();
    const notes = await client.query('SELECT title, body FROM notes');
    await client.end();
    notes.rows.should.deepEqual([{ title: 'hello', body: 'world' }]);
  });

  it('should list only forks of the source database', async () => {
    // Arrange
    await db.admin(client => client.query('CREATE DATABASE unrelated'));

    // Act
    const actual = await expectOk(subject.list());

    // Assert
    actual.should.deepEqual(['demo']);
  });

  it('should refuse to copy over an existing fork', async () => {
    // Act
    const actual = await expectErr(subject.create('demo'));

    // Assert
    actual.should.deepEqual({ kind: 'already_exists', name: 'demo' });
  });

  it('should delete a fork even while a client is connected to it', async () => {
    // Arrange
    const holder = new Client({ connectionString: db.connectionString.replace(/\/app$/, '/app_fork_demo') });
    await holder.connect();
    holder.on('error', () => undefined);

    // Act
    await expectOk(subject.delete('demo'));

    // Assert
    (await expectOk(subject.list())).should.deepEqual([]);
  });

  it('should report a fork that does not exist', async () => {
    // Act
    const actual = await expectErr(subject.delete('ghost'));

    // Assert
    actual.should.deepEqual({ kind: 'not_found', name: 'ghost' });
  });

  it('should explain how to copy a source database that is in use', async () => {
    // Arrange
    const holder = new Client({ connectionString: db.connectionString });
    await holder.connect();

    // Act
    const actual = await expectErr(subject.create('busy'));
    await holder.end();

    // Assert
    actual.kind.should.equal('provider_failed');
    (actual.kind === 'provider_failed' ? actual.message : '').should.containEql('stop every client of the source');
  }, 30_000);

  it('should report any other database failure', async () => {
    // Arrange
    const missing = new LocalPostgresBrancher(
      db.connectionString,
      new ForkNaming({ database: 'missing', bucket: 'files' }));

    // Act
    const actual = await expectErr(missing.create('demo'));

    // Assert
    actual.should.deepEqual({
      kind: 'provider_failed',
      step: 'database',
      message: 'template database "missing" does not exist',
    });
  });

  it('should refuse a fork name too long for Postgres', async () => {
    // Arrange
    const long = new LocalPostgresBrancher(
      db.connectionString,
      new ForkNaming({ database: 'a'.repeat(40), bucket: 'files' }));

    // Act
    const actual = await expectErr(long.create('abcdefghijklmnopqrstuvwx'));

    // Assert
    actual.kind.should.equal('invalid_name');
  });
});
