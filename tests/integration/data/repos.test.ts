import { afterAll, beforeAll, describe, it } from 'bun:test';
import should from 'should';
import { PgCachePurger, PgCacheStore } from '../../../src/adapters/data/cache/repo';
import { CachedForkMarkerReader, PgForkMarkerReader } from '../../../src/adapters/data/fork/reader';
import { PgJobQueue, PgJobStore } from '../../../src/adapters/data/jobs/repo';
import { PgNoteRepository, PgNotesReader } from '../../../src/adapters/data/notes/repo';
import { PgDatabase } from '../../../src/adapters/db/database';
import type { IForkMarkerReader } from '../../../src/lib/db/interfaces';
import type { ForkMarker } from '../../../src/lib/db/structures';
import { PostgresFixture } from '../../support/postgres';

describe('Postgres repositories (Testcontainers Postgres)', () => {
  let postgres: PostgresFixture;
  let db: PgDatabase;
  let tenant: string;

  beforeAll(async () => {
    postgres = await PostgresFixture.start();
    db = new PgDatabase({ connectionString: postgres.connectionString });
    tenant = await postgres.createTenant('repos');
  }, 120_000);

  afterAll(async () => {
    await db?.close();
    await postgres?.stop();
  }, 60_000);

  describe('PgNoteRepository', () => {
    it('should create, list, get, update and delete a note', async () => {
      // Act
      const actual = await db.withTenant(tenant, async sql => {
        const repo = new PgNoteRepository(sql);
        const created = await repo.create({ title: 'First', body: 'one' });
        const second = await repo.create({ title: 'Second', body: 'two' });
        const listed = await repo.list();
        const fetched = await repo.get(created.id);
        const updated = await repo.update(created.id, { title: 'Renamed' });
        const deleted = await repo.delete(second.id);
        const gone = await repo.get(second.id);
        return { created, second, listed, fetched, updated, deleted, gone };
      });

      // Assert
      actual.created.id.should.match(/^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/);
      actual.created.createdAt.should.be.instanceOf(Date);
      actual.listed.map(note => note.title).should.deepEqual(['Second', 'First']);
      (actual.fetched as { title: string }).title.should.equal('First');
      (actual.updated as { title: string; body: string }).should.containEql({ title: 'Renamed', body: 'one' });
      actual.deleted.should.be.true();
      should(actual.gone).be.undefined();
    });

    it('should report a missing note on update and delete', async () => {
      // Arrange
      const missing = crypto.randomUUID();

      // Act
      const actual = await db.withTenant(tenant, async sql => {
        const repo = new PgNoteRepository(sql);
        return { updated: await repo.update(missing, { body: 'x' }), deleted: await repo.delete(missing) };
      });

      // Assert
      should(actual.updated).be.undefined();
      actual.deleted.should.be.false();
    });

    it('should list a tenant through the reader in its own transaction', async () => {
      // Arrange
      const reader = new PgNotesReader(db);

      // Act
      const actual = await reader.list(tenant);

      // Assert
      actual.map(note => note.title).should.deepEqual(['Renamed']);
    });
  });

  describe('PgCacheStore', () => {
    it('should store, overwrite, read and delete a value', async () => {
      // Act
      const actual = await db.withTenant(tenant, async sql => {
        const store = new PgCacheStore(sql);
        await store.set('key', { n: 1 }, 60);
        await store.set('key', { n: 2 }, 60);
        const read = await store.get('key');
        await store.delete('key');
        return { read, after: await store.get('key') };
      });

      // Assert
      (actual.read as object).should.deepEqual({ n: 2 });
      should(actual.after).be.undefined();
    });

    it('should not return an expired value and should purge it', async () => {
      // Arrange
      await db.withTenant(tenant, sql => new PgCacheStore(sql).set('stale', 'old', 0));

      // Act
      const read = await db.withTenant(tenant, sql => new PgCacheStore(sql).get('stale'));
      const purged = await new PgCachePurger(db).purgeExpired();

      // Assert
      should(read).be.undefined();
      purged.should.equal(1);
    });
  });

  describe('PgForkMarkerReader', () => {
    it('should read the marker of a source database as not a fork', async () => {
      // Act
      const actual = await new PgForkMarkerReader(db).read();

      // Assert
      actual.should.deepEqual({ isFork: false });
    });

    it('should read a fork marker with its source and time', async () => {
      // Arrange
      await postgres.markFork('prod');

      // Act
      const actual = await new PgForkMarkerReader(db).read();
      await postgres.admin(client => client.query('UPDATE fork_meta SET is_fork = false, source = NULL, forked_at = NULL'));

      // Assert
      actual.isFork.should.be.true();
      (actual.source as string).should.equal('prod');
      (actual.forkedAt as Date).should.be.instanceOf(Date);
    });

    it('should treat a missing marker row as not a fork', async () => {
      // Arrange
      await postgres.admin(client => client.query('DELETE FROM fork_meta'));

      // Act
      const actual = await new PgForkMarkerReader(db).read();
      await postgres.admin(client => client.query('INSERT INTO fork_meta (singleton, is_fork) VALUES (true, false)'));

      // Assert
      actual.should.deepEqual({ isFork: false });
    });

    it('should read the marker once per cached reader', async () => {
      // Arrange
      let reads = 0;
      const inner: IForkMarkerReader = {
        read: async (): Promise<ForkMarker> => {
          reads++;
          return { isFork: false };
        },
      };
      const subject = new CachedForkMarkerReader(inner);

      // Act
      await subject.read();
      await subject.read();

      // Assert
      reads.should.equal(1);
    });
  });

  describe('PgJobQueue and PgJobStore', () => {
    const status = (id: string) =>
      postgres.admin(async client => {
        const result = await client.query('SELECT status, last_error FROM jobs WHERE id = $1', [id]);
        return result.rows[0] as { status: string; last_error: string | null };
      });

    it('should enqueue, claim, retry, fail, hold and complete jobs', async () => {
      // Arrange
      const store = new PgJobStore(db);
      const enqueued = await db.withTenant(tenant, sql =>
        new PgJobQueue(sql).enqueue({ kind: 'work', payload: { n: 1 }, outsideEffect: true }, 'queued'),
      );

      // Act
      const [claimed] = await store.claim(5, 60);
      await store.retry(enqueued.id, 0, 'try again');
      const [reclaimed] = await store.claim(5, 60);
      await store.fail(enqueued.id, 'gave up');
      const failed = await status(enqueued.id);
      await store.hold(enqueued.id);
      const held = await status(enqueued.id);
      await store.complete(enqueued.id);
      const done = await status(enqueued.id);

      // Assert
      enqueued.should.containEql({ kind: 'work', status: 'queued', outsideEffect: true, tenantId: tenant, attempts: 0 });
      should(enqueued.lockedUntil).be.undefined();
      (claimed as { attempts: number; status: string }).should.containEql({ attempts: 1, status: 'running' });
      (claimed as { lockedUntil: Date }).lockedUntil.should.be.instanceOf(Date);
      (reclaimed as { attempts: number; lastError: string }).should.containEql({ attempts: 2, lastError: 'try again' });
      failed.should.deepEqual({ status: 'failed', last_error: 'gave up' });
      held.status.should.equal('held');
      done.should.deepEqual({ status: 'done', last_error: null });
    });

    it('should store a held job without making it claimable', async () => {
      // Arrange
      const store = new PgJobStore(db);

      // Act
      const held = await db.withTenant(tenant, sql =>
        new PgJobQueue(sql).enqueue({ kind: 'mail.send', payload: {}, outsideEffect: true }, 'held'),
      );
      const actual = await store.claim(5, 60);

      // Assert
      held.status.should.equal('held');
      actual.should.have.length(0);
    });

    it('should reclaim a running job whose lease expired', async () => {
      // Arrange
      const store = new PgJobStore(db);
      const job = await db.withTenant(tenant, sql =>
        new PgJobQueue(sql).enqueue({ kind: 'work', payload: {}, outsideEffect: false }, 'queued'),
      );
      await store.claim(5, 0);

      // Act
      const [actual] = await store.claim(5, 60);
      await store.complete(job.id);

      // Assert
      (actual as { id: string; attempts: number }).should.containEql({ id: job.id, attempts: 2 });
    });
  });
});
