import { afterAll, beforeAll, describe, it } from 'bun:test';
import { expectErr, expectOk } from '@atomicloud/diene.result/test-helper';
import should from 'should';
import { PgUserRoleStore } from '../../../src/adapters/admin/pg-user-role-store';
import { PostgresFixture } from '../../support/postgres';

describe('PgUserRoleStore (Testcontainers Postgres)', () => {
  let db: PostgresFixture;
  let subject: PgUserRoleStore;

  beforeAll(async () => {
    db = await PostgresFixture.start();
    await db.admin(client =>
      client.query(`INSERT INTO "user" (id, name, email, "emailVerified", role) VALUES
        ('u1', 'Ada', 'Ada@Example.com', true, NULL),
        ('u2', 'Bob', 'bob@example.com', true, 'user')`),
    );
    subject = new PgUserRoleStore(db.connectionString);
  }, 120_000);

  afterAll(async () => {
    await db.stop();
  });

  it('should find a user by email regardless of case', async () => {
    // Act
    const ada = await expectOk(subject.find('ada@example.com'));
    const bob = await expectOk(subject.find('bob@example.com'));

    // Assert
    [ada].should.deepEqual([{ id: 'u1', email: 'Ada@Example.com' }]);
    [bob].should.deepEqual([{ id: 'u2', email: 'bob@example.com', role: 'user' }]);
  });

  it('should find nobody for an unknown email', async () => {
    // Act
    const actual = await expectOk(subject.find('eve@example.com'));

    // Assert
    should(actual).be.undefined();
  });

  it('should write the role', async () => {
    // Act
    await expectOk(subject.setRole('u2', 'user,admin'));

    // Assert
    const rows = await db.admin(
      async client => (await client.query('SELECT role FROM "user" WHERE id = $1', ['u2'])).rows,
    );
    rows.should.deepEqual([{ role: 'user,admin' }]);
  });

  it('should report a database it cannot reach', async () => {
    // Arrange
    const unreachable = new PgUserRoleStore('postgres://nobody:nothing@127.0.0.1:1/none');

    // Act
    const actual = await expectErr(unreachable.find('ada@example.com'));

    // Assert
    actual.kind.should.equal('store_failed');
  });
});
