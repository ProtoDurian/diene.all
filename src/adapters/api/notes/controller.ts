import { zValidator } from '@hono/zod-validator';
import type { Context, Hono, MiddlewareHandler } from 'hono';
import { bodyLimit } from 'hono/body-limit';
import type { z } from 'zod';
import { CacheService } from '../../../lib/cache/service';
import type { IForkMarkerReader } from '../../../lib/db/interfaces';
import type { IFileStore } from '../../../lib/files/interfaces';
import { FileKeyPolicy } from '../../../lib/files/service';
import { JobScheduler } from '../../../lib/jobs/service';
import { MailPolicy } from '../../../lib/mail/service';
import { NoteAttachmentService, NoteService, NoteShareService } from '../../../lib/notes/service';
import { PgCacheStore } from '../../data/cache/repo';
import { PgJobQueue } from '../../data/jobs/repo';
import { PgNoteRepository } from '../../data/notes/repo';
import type { AppEnv, IdentityGate, RouteModule } from '../env';
import type { ApiProblems } from '../problems';
import type { TenantTransaction } from '../tenant-transaction';
import { CreateNoteBody, NoteIdParam, ShareNoteBody, UpdateNoteBody } from './req';
import { NoteWireMapper } from './res';

export const ATTACHMENT_LIMIT_BYTES = 5 * 1024 * 1024;

export interface NotesControllerDependencies {
  readonly problems: ApiProblems;
  readonly gate: IdentityGate;
  readonly transaction: TenantTransaction;
  readonly files: IFileStore;
  readonly fork: IForkMarkerReader;
}

export class NotesController implements RouteModule {
  private readonly wire = new NoteWireMapper();
  private readonly keys = new FileKeyPolicy();
  private readonly mail = new MailPolicy();

  constructor(private readonly deps: NotesControllerDependencies) {}

  register(app: Hono<AppEnv>): void {
    const { transaction, problems } = this.deps;
    // Hono context variables are invariant; the gate only sets `identity`, which AppEnv declares.
    const gate = this.deps.gate as unknown as MiddlewareHandler<AppEnv>;
    app.use('/api/notes', gate, transaction.handler);
    app.use('/api/notes/*', gate, transaction.handler);

    const json = <S extends z.ZodType>(schema: S) => this.validate('json', schema);
    const id = this.validate('param', NoteIdParam);

    app.get('/api/notes', async c => c.json(this.wire.list(await this.notes(c).list())));

    app.post('/api/notes', json(CreateNoteBody), async c =>
      c.json(this.wire.note(await this.notes(c).create(c.req.valid('json'))), 201),
    );

    app.get('/api/notes/:id', id, c =>
      this.notes(c)
        .get(c.req.valid('param').id)
        .match({ ok: note => c.json(this.wire.note(note)), err: error => problems.entityNotFound('note', error.id) }),
    );

    app.patch('/api/notes/:id', id, json(UpdateNoteBody), c =>
      this.notes(c)
        .update(c.req.valid('param').id, c.req.valid('json'))
        .match({ ok: note => c.json(this.wire.note(note)), err: error => problems.entityNotFound('note', error.id) }),
    );

    app.delete('/api/notes/:id', id, c =>
      this.notes(c)
        .delete(c.req.valid('param').id)
        .match({
          ok: async deleted => {
            await this.attachments(c).remove(deleted);
            return c.body(null, 204);
          },
          err: error => problems.entityNotFound('note', error.id),
        }),
    );

    app.post('/api/notes/:id/share', id, json(ShareNoteBody), async c => {
      const fork = await this.deps.fork.read();
      return this.share(c, fork.isFork)
        .share(c.req.valid('param').id, c.req.valid('json').to)
        .match({
          ok: job => {
            c.set('kick', true);
            return c.json(this.wire.share(job), 202);
          },
          err: error => problems.entityNotFound('note', error.id),
        });
    });

    app.put(
      '/api/notes/:id/attachment',
      bodyLimit({ maxSize: ATTACHMENT_LIMIT_BYTES, onError: () => problems.payloadTooLarge(ATTACHMENT_LIMIT_BYTES) }),
      id,
      async c => {
        const upload = {
          body: await c.req.arrayBuffer(),
          contentType: c.req.header('content-type') ?? 'application/octet-stream',
        };
        return this.attachments(c)
          .put(c.req.valid('param').id, upload)
          .match({ ok: () => c.body(null, 204), err: error => problems.entityNotFound('note', error.id) });
      },
    );

    app.get('/api/notes/:id/attachment', id, c =>
      this.attachments(c)
        .get(c.req.valid('param').id)
        .match({
          ok: file =>
            new Response(file.body, {
              headers: { 'content-type': file.contentType, 'content-length': String(file.size) },
            }),
          err: error => problems.entityNotFound(error.kind === 'note_not_found' ? 'note' : 'attachment', error.id),
        }),
    );
  }

  private validate<T extends 'json' | 'param', S extends z.ZodType>(target: T, schema: S) {
    return zValidator(target, schema, result => {
      if (!result.success) return this.deps.problems.invalid(result.error.issues);
    });
  }

  private notes(c: Context<AppEnv>): NoteService {
    return new NoteService(new PgNoteRepository(c.var.sql), new CacheService(new PgCacheStore(c.var.sql)));
  }

  private share(c: Context<AppEnv>, isFork: boolean): NoteShareService {
    return new NoteShareService(
      new PgNoteRepository(c.var.sql),
      new JobScheduler(new PgJobQueue(c.var.sql), isFork),
      this.mail,
    );
  }

  private attachments(c: Context<AppEnv>): NoteAttachmentService {
    return new NoteAttachmentService(
      new PgNoteRepository(c.var.sql),
      this.deps.files,
      this.keys,
      c.var.identity.tenantId,
    );
  }
}
