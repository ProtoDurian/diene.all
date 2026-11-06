import { afterAll, beforeAll, describe, it } from 'bun:test';
import { expectErr, expectOk } from '@atomicloud/diene.result/test-helper';
import 'should';
import { PgForkSanitizer } from '../../../src/adapters/fork/pg-fork-sanitizer';
import { RandomSecretGenerator } from '../../../src/adapters/fork/random-secret-generator';
import { PostgresFixture } from '../../support/postgres';
import { ForkSeeder } from './seed';

describe('PgForkSanitizer (Testcontainers Postgres)', () => {
  let db: PostgresFixture;
  let seededSecret: string;
  const subject = new PgForkSanitizer(new RandomSecretGenerator());

  beforeAll(async () => {
    db = await PostgresFixture.start();
    const tenantId = await db.createTenant('acme');
    seededSecret = (await db.admin(client => new ForkSeeder().seed(client, tenantId))).clientSecret;
  }, 120_000);

  afterAll(async () => {
    await db.stop();
  });

  it('should sign everyone out, disable keys, rotate secrets, hold jobs and mark the fork', async () => {
    // Arrange
    const branch = { name: 'app', connectionString: db.connectionString };

    // Act
    const actual = await expectOk(subject.sanitize(branch, { source: 'production' }));

    // Assert
    actual.should.deepEqual({ sessionsDeleted: 2, apiKeysDisabled: 2, jobsHeld: 2, secretRowsRotated: 7 });
    const state = await db.admin(async client => {
      const one = async (sql: string) => (await client.query(sql)).rows;
      return {
        sessions: await one('SELECT id FROM "session"'),
        keys: await one('SELECT id, enabled FROM "apikey" ORDER BY id'),
        tokens: await one(
          'SELECT (SELECT count(*) FROM "verification") + (SELECT count(*) FROM "oauthAccessToken") + (SELECT count(*) FROM "oauthRefreshToken") + (SELECT count(*) FROM "jwks") AS n',
        ),
        accounts: await one('SELECT id, "accessToken", "refreshToken", "idToken" FROM "account" ORDER BY id'),
        invitations: await one('SELECT id, status FROM "invitation" ORDER BY id'),
        clients: await one('SELECT "clientId", "clientSecret" FROM "oauthClient" ORDER BY "clientId"'),
        jobs: await one('SELECT kind, status FROM jobs ORDER BY kind, status'),
        meta: await one('SELECT is_fork, source, forked_at IS NOT NULL AS stamped FROM fork_meta'),
      };
    });
    state.sessions.length.should.equal(0);
    state.keys.should.deepEqual([
      { id: 'k1', enabled: false },
      { id: 'k2', enabled: false },
    ]);
    state.tokens.should.deepEqual([{ n: '0' }]);
    state.accounts.should.deepEqual([
      { id: 'a1', accessToken: null, refreshToken: null, idToken: null },
      { id: 'a2', accessToken: null, refreshToken: null, idToken: null },
    ]);
    state.invitations.should.deepEqual([
      { id: 'i1', status: 'canceled' },
      { id: 'i2', status: 'accepted' },
    ]);
    state.clients[0].clientId.should.equal('confidential');
    state.clients[0].clientSecret.should.not.equal(seededSecret);
    state.clients[0].clientSecret.length.should.be.above(20);
    state.clients[1].should.deepEqual({ clientId: 'public-cli', clientSecret: null });
    state.jobs.should.deepEqual([
      { kind: 'call-webhook', status: 'held' },
      { kind: 'rebuild-cache', status: 'queued' },
      { kind: 'send-mail', status: 'done' },
      { kind: 'send-mail', status: 'held' },
    ]);
    state.meta.should.deepEqual([{ is_fork: true, source: 'production', stamped: true }]);
  });

  it('should roll back and report a database that is not an aseity schema', async () => {
    // Arrange
    await db.admin(client => client.query('CREATE DATABASE blank'));
    const url = new URL(db.connectionString);
    url.pathname = '/blank';

    // Act
    const actual = await expectErr(
      subject.sanitize({ name: 'blank', connectionString: url.toString() }, { source: 'x' }),
    );

    // Assert
    actual.kind.should.equal('provider_failed');
    (actual.kind === 'provider_failed' ? actual.step : '').should.equal('sanitize');
  });
});
