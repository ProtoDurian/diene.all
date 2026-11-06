import { afterAll, beforeAll, describe, it } from 'bun:test';
import 'should';
import { MinioFixture } from '../../support/minio';
import { PostgresFixture } from '../../support/postgres';
import { TEST_TENANT_HEADER } from '../../support/test-auth';
import { WranglerDev } from '../../support/wrangler-dev';

const AUTH_SECRET = 'e2e-only-secret-that-is-at-least-32-characters';

describe('Worker on local workerd (wrangler dev) against Postgres', () => {
  let postgres: PostgresFixture;
  let minio: MinioFixture;
  let app: WranglerDev;
  let tenant: string;

  beforeAll(async () => {
    [postgres, minio] = await Promise.all([PostgresFixture.start(), MinioFixture.start()]);
    tenant = await postgres.createTenant('e2e');
    app = await WranglerDev.start({
      entry: 'tests/support/e2e-worker.ts',
      connectionString: postgres.connectionString,
      vars: { ...minio.env, MAIL_API_KEY: '' },
    });
  }, 240_000);

  afterAll(async () => {
    await app?.stop();
    await Promise.all([postgres?.stop(), minio?.stop()]);
  }, 60_000);

  it('should serve health from the Hyperdrive-bound database', async () => {
    // Act
    const response = await app.fetch('/api/health');

    // Assert
    response.status.should.equal(200);
    ((await response.json()) as object).should.deepEqual({ status: 'ok', fork: false });
  });

  it('should create, list, update and delete a tenant note through the Worker', async () => {
    // Arrange
    const headers = { [TEST_TENANT_HEADER]: tenant, 'content-type': 'application/json' };

    // Act
    const created = await app.fetch('/api/notes', {
      method: 'POST',
      headers,
      body: JSON.stringify({ title: 'From workerd', body: 'hello' }),
    });
    const note = (await created.json()) as { id: string };
    const listed = (await (await app.fetch('/api/notes', { headers })).json()) as { items: { id: string }[] };
    const patched = await app.fetch(`/api/notes/${note.id}`, {
      method: 'PATCH',
      headers,
      body: JSON.stringify({ body: 'changed' }),
    });
    const deleted = await app.fetch(`/api/notes/${note.id}`, { method: 'DELETE', headers });
    const stored = await postgres.admin(async client => (await client.query('SELECT tenant_id FROM notes')).rows);

    // Assert
    created.status.should.equal(201);
    listed.items.map(item => item.id).should.deepEqual([note.id]);
    ((await patched.json()) as { body: string }).body.should.equal('changed');
    deleted.status.should.equal(204);
    stored.should.have.length(0);
  });

  it('should store and serve an attachment through the S3 binding settings', async () => {
    // Arrange
    const headers = { [TEST_TENANT_HEADER]: tenant };
    const created = await app.fetch('/api/notes', {
      method: 'POST',
      headers: { ...headers, 'content-type': 'application/json' },
      body: JSON.stringify({ title: 'File', body: 'x' }),
    });
    const note = (await created.json()) as { id: string };

    // Act
    const put = await app.fetch(`/api/notes/${note.id}/attachment`, {
      method: 'PUT',
      headers: { ...headers, 'content-type': 'text/plain' },
      body: 'workerd file',
    });
    const got = await app.fetch(`/api/notes/${note.id}/attachment`, { headers });

    // Assert
    put.status.should.equal(204);
    (await got.text()).should.equal('workerd file');
  });

  it('should hold shared mail in a fork and only sink it', async () => {
    // Arrange
    const headers = { [TEST_TENANT_HEADER]: tenant, 'content-type': 'application/json' };
    const created = await app.fetch('/api/notes', {
      method: 'POST',
      headers,
      body: JSON.stringify({ title: 'Forked', body: 'x' }),
    });
    const note = (await created.json()) as { id: string };
    await postgres.markFork();

    // Act
    const shared = await app.fetch(`/api/notes/${note.id}/share`, {
      method: 'POST',
      headers,
      body: JSON.stringify({ to: 'b@example.com' }),
    });

    // Assert
    shared.status.should.equal(202);
    ((await shared.json()) as { status: string }).status.should.equal('held');
  });

  it('should run the real entry with Better Auth and gate tenant routes', async () => {
    // Arrange
    const real = await WranglerDev.start({
      connectionString: postgres.connectionString,
      vars: { ...minio.env, BETTER_AUTH_SECRET: AUTH_SECRET, MAIL_API_KEY: '' },
    });

    // Act
    const health = await real.fetch('/api/health');
    const notes = await real.fetch('/api/notes');
    const notesType = notes.headers.get('content-type');
    const problem = (await notes.json()) as { type: string };
    await real.stop();

    // Assert
    health.status.should.equal(200);
    notes.status.should.equal(401);
    (notesType as string).should.equal('application/problem+json');
    problem.type.should.endWith('/unauthenticated');
  }, 120_000);
});
