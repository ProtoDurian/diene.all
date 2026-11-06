import { afterAll, beforeAll, describe, it } from 'bun:test';
import type { Server } from 'bun';
import 'should';
import { ATTACHMENT_LIMIT_BYTES } from '../../../src/adapters/api/notes/controller';
import { WorkerRuntime, type WorkerEnv } from '../../../src/adapters/api/runtime';
import { BackgroundWork, RecordingLog } from '../../support/background';
import { MinioFixture } from '../../support/minio';
import { PostgresFixture } from '../../support/postgres';
import { HeaderAuthProvider, TEST_TENANT_HEADER } from '../../support/test-auth';

const APP_URL = 'http://aseity.test';
const UUID_V7 = /^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/;
const INSTANT = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/;

interface Problem {
  readonly type: string;
  readonly status: number;
  readonly data: Record<string, unknown>;
}

describe('WorkerRuntime over HTTP (Testcontainers Postgres + MinIO)', () => {
  let postgres: PostgresFixture;
  let minio: MinioFixture;
  let mailApi: Server<undefined>;
  const delivered: unknown[] = [];
  let env: WorkerEnv;
  let log: RecordingLog;
  let runtime: WorkerRuntime;
  let tenantA: string;
  let tenantB: string;

  beforeAll(async () => {
    [postgres, minio] = await Promise.all([PostgresFixture.start(), MinioFixture.start()]);
    mailApi = Bun.serve({
      port: 0,
      fetch: async request => {
        delivered.push(await request.json());
        return Response.json({ id: 'sent' });
      },
    });
    env = {
      HYPERDRIVE: { connectionString: postgres.connectionString },
      APP_URL,
      MAIL_FROM: 'app@example.com',
      MAIL_API_KEY: crypto.randomUUID(),
      ...minio.env,
    };
    log = new RecordingLog();
    runtime = new WorkerRuntime(new HeaderAuthProvider(), {
      log,
      mailEndpoint: `http://127.0.0.1:${mailApi.port}/emails`,
    });
    tenantA = await postgres.createTenant('api-a');
    tenantB = await postgres.createTenant('api-b');
  }, 180_000);

  afterAll(async () => {
    mailApi?.stop(true);
    await Promise.all([postgres?.stop(), minio?.stop()]);
  }, 60_000);

  const call = async (
    method: string,
    path: string,
    options: {
      tenant?: string;
      json?: unknown;
      body?: RequestInit['body'];
      headers?: Record<string, string>;
      target?: WorkerEnv;
    } = {},
  ) => {
    const headers = new Headers(options.headers);
    if (options.tenant !== undefined) headers.set(TEST_TENANT_HEADER, options.tenant);
    let body = options.body;
    if (options.json !== undefined) {
      headers.set('content-type', 'application/json');
      body = JSON.stringify(options.json);
    }
    const background = new BackgroundWork();
    const response = await runtime.fetch(
      new Request(`${APP_URL}${path}`, { method, headers, body }),
      options.target ?? env,
      background,
    );
    await background.settle();
    return response;
  };

  const problem = async (response: Response, status: number, id: string): Promise<Problem> => {
    response.status.should.equal(status);
    (response.headers.get('content-type') as string).should.equal('application/problem+json');
    const actual = (await response.json()) as Problem;
    actual.type.should.endWith(`/${id}`);
    actual.type.should.startWith(`${APP_URL}/docs/`);
    return actual;
  };

  const createNote = async (tenant: string, title = 'Plan') => {
    const response = await call('POST', '/api/notes', { tenant, json: { title, body: 'Ship it' } });
    return (await response.json()) as { id: string; title: string; body: string; createdAt: string };
  };

  it('should report health with the fork flag', async () => {
    // Act
    const response = await call('GET', '/api/health');

    // Assert
    response.status.should.equal(200);
    ((await response.json()) as object).should.deepEqual({ status: 'ok', fork: false });
  });

  it('should report the database as unavailable when it cannot be reached', async () => {
    // Arrange
    const target = { ...env, HYPERDRIVE: { connectionString: 'postgres://nobody:none@127.0.0.1:1/none' } };

    // Act
    const response = await call('GET', '/api/health', { target });

    // Assert
    const actual = await problem(response, 503, 'service_unavailable');
    actual.data.should.deepEqual({ dependency: 'database' });
  });

  it('should leave tenant routes to the gate when no caller is known', async () => {
    // Act
    const response = await call('GET', '/api/notes');

    // Assert
    response.status.should.equal(401);
  });

  it('should create a note in the wire format', async () => {
    // Act
    const response = await call('POST', '/api/notes', { tenant: tenantA, json: { title: '  Plan ', body: 'Ship it' } });

    // Assert
    response.status.should.equal(201);
    const actual = (await response.json()) as Record<string, string>;
    Object.keys(actual).sort().should.deepEqual(['body', 'createdAt', 'id', 'title']);
    (actual.id as string).should.match(UUID_V7);
    (actual.createdAt as string).should.match(INSTANT);
    (actual.title as string).should.equal('Plan');
  });

  it('should reject an invalid note with a validation problem', async () => {
    // Act
    const response = await call('POST', '/api/notes', { tenant: tenantA, json: { title: '', extra: true } });

    // Assert
    const actual = await problem(response, 400, 'validation_error');
    const issues = actual.data.issues as { path: string[] }[];
    issues.map(issue => issue.path.join('.')).should.containDeep(['title', 'body']);
  });

  it('should list, get and update notes of the calling tenant only', async () => {
    // Arrange
    const note = await createNote(tenantA, 'Listed');

    // Act
    const listed = (await (await call('GET', '/api/notes', { tenant: tenantA })).json()) as { items: { id: string }[] };
    const fetched = await call('GET', `/api/notes/${note.id}`, { tenant: tenantA });
    const patched = await call('PATCH', `/api/notes/${note.id}`, { tenant: tenantA, json: { body: 'Changed' } });
    const otherList = (await (await call('GET', '/api/notes', { tenant: tenantB })).json()) as { items: unknown[] };
    const otherGet = await call('GET', `/api/notes/${note.id}`, { tenant: tenantB });

    // Assert
    listed.items.map(item => item.id).should.containEql(note.id);
    ((await fetched.json()) as { title: string }).title.should.equal('Listed');
    ((await patched.json()) as { body: string }).body.should.equal('Changed');
    otherList.items.should.deepEqual([]);
    (await problem(otherGet, 404, 'entity_not_found')).data.should.deepEqual({ entityType: 'note', id: note.id });
  });

  it('should reject a malformed id and an empty patch', async () => {
    // Arrange
    const note = await createNote(tenantA);

    // Act
    const badId = await call('GET', '/api/notes/not-a-uuid', { tenant: tenantA });
    const emptyPatch = await call('PATCH', `/api/notes/${note.id}`, { tenant: tenantA, json: {} });

    // Assert
    await problem(badId, 400, 'validation_error');
    await problem(emptyPatch, 400, 'validation_error');
  });

  it('should answer not found for every note route on an unknown id', async () => {
    // Arrange
    const missing = crypto.randomUUID();
    const tenant = tenantA;

    // Act
    const responses = await Promise.all([
      call('PATCH', `/api/notes/${missing}`, { tenant, json: { title: 'x' } }),
      call('DELETE', `/api/notes/${missing}`, { tenant }),
      call('POST', `/api/notes/${missing}/share`, { tenant, json: { to: 'b@example.com' } }),
      call('PUT', `/api/notes/${missing}/attachment`, { tenant, body: 'x', headers: { 'content-type': 'text/plain' } }),
      call('GET', `/api/notes/${missing}/attachment`, { tenant }),
    ]);

    // Assert
    for (const response of responses) {
      (await problem(response, 404, 'entity_not_found')).data.should.deepEqual({ entityType: 'note', id: missing });
    }
  });

  it('should share a note by mail through a job that runs after the response', async () => {
    // Arrange
    const note = await createNote(tenantA, 'Shared');
    delivered.length = 0;

    // Act
    const response = await call('POST', `/api/notes/${note.id}/share`, {
      tenant: tenantA,
      json: { to: 'b@example.com' },
    });

    // Assert
    response.status.should.equal(202);
    const actual = (await response.json()) as { jobId: string; status: string };
    actual.status.should.equal('queued');
    delivered.should.deepEqual([{ from: 'app@example.com', to: 'b@example.com', subject: 'Shared', text: 'Ship it' }]);
    const [job] = await postgres.admin(
      async client => (await client.query('SELECT status FROM jobs WHERE id = $1', [actual.jobId])).rows,
    );
    job.status.should.equal('done');
  });

  it('should hold shared mail and send nothing in a fork', async () => {
    // Arrange
    const note = await createNote(tenantA, 'Forked');
    delivered.length = 0;
    await postgres.markFork();

    // Act
    const response = await call('POST', `/api/notes/${note.id}/share`, {
      tenant: tenantA,
      json: { to: 'b@example.com' },
    });
    const health = (await (await call('GET', '/api/health')).json()) as { fork: boolean };
    await postgres.admin(client => client.query('UPDATE fork_meta SET is_fork = false'));

    // Assert
    ((await response.json()) as { status: string }).status.should.equal('held');
    delivered.should.deepEqual([]);
    health.fork.should.be.true();
  });

  it('should store, serve and delete a note attachment', async () => {
    // Arrange
    const note = await createNote(tenantA, 'With file');

    // Act
    const missing = await call('GET', `/api/notes/${note.id}/attachment`, { tenant: tenantA });
    const put = await call('PUT', `/api/notes/${note.id}/attachment`, {
      tenant: tenantA,
      body: 'file body',
      headers: { 'content-type': 'text/plain' },
    });
    const got = await call('GET', `/api/notes/${note.id}/attachment`, { tenant: tenantA });
    const keys = await minio.objectKeys();
    const deleted = await call('DELETE', `/api/notes/${note.id}`, { tenant: tenantA });
    const keysAfter = await minio.objectKeys();

    // Assert
    (await problem(missing, 404, 'entity_not_found')).data.should.deepEqual({ entityType: 'attachment', id: note.id });
    put.status.should.equal(204);
    (got.headers.get('content-type') as string).should.equal('text/plain');
    (await got.text()).should.equal('file body');
    keys.should.containEql(`tenants/${tenantA}/notes/${note.id}/attachment`);
    deleted.status.should.equal(204);
    keysAfter.should.not.containEql(`tenants/${tenantA}/notes/${note.id}/attachment`);
  });

  it('should store an attachment without a content type as binary', async () => {
    // Arrange
    const note = await createNote(tenantA, 'Binary');

    // Act
    await call('PUT', `/api/notes/${note.id}/attachment`, { tenant: tenantA, body: new Uint8Array([1, 2, 3]) });
    const got = await call('GET', `/api/notes/${note.id}/attachment`, { tenant: tenantA });

    // Assert
    (got.headers.get('content-type') as string).should.equal('application/octet-stream');
  });

  it('should refuse an attachment over the size limit', async () => {
    // Arrange
    const note = await createNote(tenantA, 'Too big');

    // Act
    const response = await call('PUT', `/api/notes/${note.id}/attachment`, {
      tenant: tenantA,
      body: new Uint8Array(ATTACHMENT_LIMIT_BYTES + 1),
      headers: { 'content-type': 'application/octet-stream' },
    });

    // Assert
    (await problem(response, 413, 'payload_too_large')).data.should.deepEqual({ limitBytes: ATTACHMENT_LIMIT_BYTES });
  });

  it('should answer an unknown route with a problem', async () => {
    // Act
    const response = await call('GET', '/api/nope');

    // Assert
    (await problem(response, 404, 'route_not_found')).data.should.deepEqual({ method: 'GET', path: '/api/nope' });
  });

  it('should roll back and answer an internal problem when a handler throws', async () => {
    // Arrange
    const unknownTenant = crypto.randomUUID();
    log.errors.length = 0;

    // Act
    const response = await call('POST', '/api/notes', { tenant: unknownTenant, json: { title: 'Orphan', body: 'x' } });
    const rows = await postgres.admin(
      async client => (await client.query("SELECT id FROM notes WHERE title = 'Orphan'")).rows,
    );

    // Assert
    await problem(response, 500, 'internal_error');
    rows.should.have.length(0);
    log.errors.map(entry => entry.message).should.containEql('unhandled request error');
  });

  it('should answer a plain internal problem when request setup fails', async () => {
    // Arrange
    const { S3_BUCKET: _bucket, ...target } = env;
    log.errors.length = 0;

    // Act
    const response = await call('GET', '/api/health', { target: target as WorkerEnv });

    // Assert
    response.status.should.equal(500);
    ((await response.json()) as { title: string }).title.should.equal('Internal Error');
    (log.errors[0]?.fields.reason as string).should.containEql('invalid storage settings: S3_BUCKET');
  });

  it('should answer a plain internal problem when the Hyperdrive binding is missing', async () => {
    // Arrange
    const { HYPERDRIVE: _binding, ...target } = env;
    log.errors.length = 0;
    const background = new BackgroundWork();

    // Act
    const response = await runtime.fetch(new Request(`${APP_URL}/api/health`), target as WorkerEnv, background);
    await runtime.scheduled(target as WorkerEnv, background);
    await background.settle();

    // Assert
    response.status.should.equal(500);
    (response.headers.get('content-type') as string).should.equal('application/problem+json');
    log.errors.map(entry => entry.message).should.deepEqual(['request setup failed', 'scheduled setup failed']);
  });

  it('should drain due jobs and purge expired cache on the cron tick', async () => {
    // Arrange
    delivered.length = 0;
    log.infos.length = 0;
    await postgres.admin(async client => {
      await client.query(
        "INSERT INTO jobs (tenant_id, kind, payload, outside_effect) VALUES ($1, 'mail.send', $2, true)",
        [tenantB, JSON.stringify({ to: 'c@example.com', subject: 'Cron', text: 'tick' })],
      );
      await client.query(
        "INSERT INTO cache_entries (tenant_id, key, value, expires_at) VALUES ($1, 'old', '1', now() - interval '1 minute')",
        [tenantB],
      );
    });
    const background = new BackgroundWork();

    // Act
    await runtime.scheduled(env, background);
    await background.settle();
    const cache = await postgres.admin(
      async client => (await client.query("SELECT key FROM cache_entries WHERE key = 'old'")).rows,
    );

    // Assert
    delivered.should.deepEqual([{ from: 'app@example.com', to: 'c@example.com', subject: 'Cron', text: 'tick' }]);
    (log.infos.find(entry => entry.message === 'jobs drained')?.fields.done as number).should.equal(1);
    cache.should.have.length(0);
  });

  it('should log a cron tick that cannot reach the database', async () => {
    // Arrange
    log.errors.length = 0;
    const background = new BackgroundWork();
    const target = { ...env, HYPERDRIVE: { connectionString: 'postgres://nobody:none@127.0.0.1:1/none' } };

    // Act
    await runtime.scheduled(target, background);
    await background.settle();

    // Assert
    log.errors.map(entry => entry.message).should.deepEqual(['background work failed']);
  });

  it('should log a cron tick whose settings are invalid', async () => {
    // Arrange
    log.errors.length = 0;
    const background = new BackgroundWork();
    const { MAIL_FROM: _from, ...target } = env;

    // Act
    await runtime.scheduled(target as WorkerEnv, background);
    await background.settle();

    // Assert
    log.errors.map(entry => entry.message).should.deepEqual(['scheduled setup failed']);
  });

  it('should log to the console when no log is given', async () => {
    // Arrange
    const quiet = new WorkerRuntime(new HeaderAuthProvider());
    const background = new BackgroundWork();

    // Act
    const response = await quiet.fetch(new Request(`${APP_URL}/api/health`), env, background);
    await background.settle();

    // Assert
    response.status.should.equal(200);
  });
});
