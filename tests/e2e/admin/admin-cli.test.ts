import { afterAll, beforeAll, describe, it } from 'bun:test';
import 'should';
import { PostgresFixture } from '../../support/postgres';
import { CliRunner } from '../cli-runner';

describe('aseity admin grant (CLI, Postgres)', () => {
  let db: PostgresFixture;
  let cli: CliRunner;

  const roleOf = (email: string) =>
    db.admin(async client => (await client.query('SELECT role FROM "user" WHERE email = $1', [email])).rows);

  beforeAll(async () => {
    db = await PostgresFixture.start();
    await db.admin(client =>
      client.query(`INSERT INTO "user" (id, name, email, "emailVerified", role) VALUES
        ('u1', 'Ada', 'ada@example.com', true, NULL),
        ('u2', 'Bob', 'bob@example.com', true, 'user')`),
    );
    cli = new CliRunner({ ASEITY_DATABASE__URL: db.connectionString });
  }, 120_000);

  afterAll(async () => {
    await db.stop();
  });

  it('should make the first signed-up user an admin', async () => {
    // Act
    const actual = await cli.json('admin', 'grant', 'Ada@Example.com');

    // Assert
    actual.should.deepEqual({ email: 'ada@example.com', role: 'admin', changed: true });
    (await roleOf('ada@example.com')).should.deepEqual([{ role: 'admin' }]);
  }, 60_000);

  it('should add admin beside existing roles and be idempotent', async () => {
    // Act
    const first = await cli.json('admin', 'grant', 'bob@example.com');
    const second = await cli.json('admin', 'grant', 'bob@example.com');

    // Assert
    first.should.deepEqual({ email: 'bob@example.com', role: 'user,admin', changed: true });
    second.should.deepEqual({ email: 'bob@example.com', role: 'user,admin', changed: false });
    (await roleOf('bob@example.com')).should.deepEqual([{ role: 'user,admin' }]);
  }, 60_000);

  it('should refuse an email nobody signed up with', async () => {
    // Act
    const actual = await cli.run('admin', 'grant', 'eve@example.com');

    // Assert
    actual.code.should.equal(1);
    actual.stderr.should.containEql('no user signed up with eve@example.com');
  }, 60_000);
});
