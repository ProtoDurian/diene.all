import { afterAll, beforeAll, describe, it } from 'bun:test';
import { mkdtemp, readFile, rm, stat } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { Client } from 'pg';
import 'should';
import { PostgresFixture } from '../../support/postgres';
import { MinioFixture } from '../../integration/fork/minio';
import { ForkSeeder } from '../../integration/fork/seed';

const ROOT = resolve(import.meta.dir, '../../..');

interface Run {
  readonly code: number;
  readonly stdout: string;
  readonly stderr: string;
}

// Drives the real CLI entry point the way a user would, against real Postgres and MinIO.
class CliRunner {
  constructor(private readonly env: Record<string, string>) {}

  async run(...args: string[]): Promise<Run> {
    const child = Bun.spawn(['bun', 'cli/index.ts', ...args], {
      cwd: ROOT,
      env: { PATH: process.env.PATH ?? '', HOME: process.env.HOME ?? '', ...this.env },
      stdout: 'pipe',
      stderr: 'pipe',
    });
    const [stdout, stderr, code] = await Promise.all([
      new Response(child.stdout).text(),
      new Response(child.stderr).text(),
      child.exited,
    ]);
    return { code, stdout, stderr };
  }

  async json(...args: string[]): Promise<object> {
    const result = await this.run(...args, '--json');
    if (result.code !== 0) throw new Error(`aseity ${args.join(' ')} exited ${result.code}: ${result.stderr}`);
    return JSON.parse(result.stdout) as object;
  }
}

class ForkDatabase {
  constructor(private readonly url: string) {}

  async rows(sql: string): Promise<unknown[]> {
    const client = new Client({ connectionString: this.url });
    await client.connect();
    try {
      return (await client.query(sql)).rows;
    } finally {
      await client.end();
    }
  }
}

describe('aseity fork (CLI, Postgres + MinIO)', () => {
  let db: PostgresFixture;
  let minio: MinioFixture;
  let cli: CliRunner;
  let scratch: string;
  let secretFile: string;

  beforeAll(async () => {
    [db, minio] = await Promise.all([PostgresFixture.start({ migrate: false }), MinioFixture.start()]);
    scratch = await mkdtemp(join(tmpdir(), 'aseity-fork-'));
    secretFile = join(scratch, 'fork.env');
    cli = new CliRunner({
      ASEITY_DATABASE__URL: db.connectionString,
      ASEITY_STORAGE__ENDPOINT: minio.connection.endpoint,
      ASEITY_STORAGE__BUCKET: 'files',
      ASEITY_STORAGE__ACCESS_KEY_ID: minio.connection.accessKeyId,
      ASEITY_STORAGE__SECRET_ACCESS_KEY: minio.connection.secretAccessKey,
    });
    await minio.createBucket('files');
    await minio.put('files', 'tenants/acme/logo.png', 'png-bytes');
  }, 180_000);

  afterAll(async () => {
    await Promise.all([db.stop(), minio.stop(), rm(scratch, { recursive: true, force: true })]);
  });

  it('should migrate the source database', async () => {
    // Act
    const actual = (await cli.json('migrate')) as { applied: string[] };

    // Assert
    actual.applied.should.containEql('0006_fork_meta');
    actual.applied.should.containEql('0100_auth');
  }, 60_000);

  it('should fork a copy that is signed out, keyless, re-keyed, held and marked', async () => {
    // Arrange
    const tenantId = await db.createTenant('acme');
    await db.admin(async client => {
      await new ForkSeeder().seed(client, tenantId);
      await client.query("INSERT INTO notes (tenant_id, title, body) VALUES ($1, 'hello', 'world')", [tenantId]);
    });

    // Act
    const actual = await cli.json('fork', 'create', 'demo', '--secret-file', secretFile);

    // Assert
    actual.should.deepEqual({
      name: 'demo',
      database: 'app_fork_demo',
      bucket: 'files-fork-demo',
      secretFile,
      sanitized: { sessionsDeleted: 2, apiKeysDisabled: 2, jobsHeld: 2, secretRowsRotated: 7 },
    });
    const fork = new ForkDatabase(db.connectionString.replace(/\/app$/, '/app_fork_demo'));
    (await fork.rows('SELECT title FROM notes')).should.deepEqual([{ title: 'hello' }]);
    (await fork.rows('SELECT id FROM "session"')).should.deepEqual([]);
    (await fork.rows('SELECT DISTINCT enabled FROM "apikey"')).should.deepEqual([{ enabled: false }]);
    (await fork.rows('SELECT id FROM "jwks" UNION ALL SELECT id FROM "verification"')).should.deepEqual([]);
    (await fork.rows(`SELECT count(*)::int AS n FROM jobs WHERE status = 'held'`)).should.deepEqual([{ n: 2 }]);
    (await fork.rows('SELECT is_fork, source FROM fork_meta')).should.deepEqual([{ is_fork: true, source: 'app' }]);
    (await minio.get('files-fork-demo', 'tenants/acme/logo.png')).should.equal('png-bytes');
    const source = new ForkDatabase(db.connectionString);
    (await source.rows('SELECT count(*)::int AS n FROM "session"')).should.deepEqual([{ n: 2 }]);
    (await source.rows('SELECT is_fork FROM fork_meta')).should.deepEqual([{ is_fork: false }]);
    const secrets = await readFile(secretFile, 'utf8');
    secrets.should.match(/^BETTER_AUTH_SECRET=[A-Za-z0-9_-]{43}$/m);
    secrets.should.containEql('CLOUDFLARE_HYPERDRIVE_LOCAL_CONNECTION_STRING_HYPERDRIVE=postgres://');
    ((await stat(secretFile)).mode & 0o777).should.equal(0o600);
  }, 120_000);

  it('should list the fork and refuse a second one with the same name', async () => {
    // Act
    const listed = await cli.json('fork', 'list');
    const again = await cli.run('fork', 'create', 'demo', '--secret-file', join(scratch, 'again.env'), '--json');

    // Assert
    listed.should.deepEqual([{ name: 'demo', hasDatabase: true, hasBucket: true }]);
    again.code.should.equal(1);
    JSON.parse(again.stderr).should.deepEqual({ error: { kind: 'already_exists', name: 'demo' } });
  }, 60_000);

  it('should delete the fork and leave the source in place', async () => {
    // Act
    const deleted = await cli.json('fork', 'delete', 'demo');
    const listed = await cli.json('fork', 'list');

    // Assert
    deleted.should.deepEqual({ name: 'demo', database: true, bucket: true });
    listed.should.deepEqual([]);
    (await minio.buckets()).should.deepEqual(['files']);
  }, 60_000);

  it('should explain a bad name and missing configuration', async () => {
    // Act
    const badName = await cli.run('fork', 'delete', 'Not_Valid');
    const unconfigured = await new CliRunner({}).run('fork', 'list');

    // Assert
    badName.code.should.equal(1);
    badName.stderr.should.containEql("fork name 'Not_Valid' must be lowercase letters");
    unconfigured.code.should.equal(2);
    unconfigured.stderr.should.containEql('database.url');
  }, 60_000);
});
