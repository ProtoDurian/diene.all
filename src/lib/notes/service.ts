import { Opt, type Result } from '@atomicloud/diene.result';
import type { CacheService } from '../cache/service';
import type { IFileStore } from '../files/interfaces';
import type { FileKeyPolicy } from '../files/service';
import type { FileUpload, StoredFile } from '../files/structures';
import type { JobScheduler } from '../jobs/service';
import type { Job } from '../jobs/structures';
import type { MailPolicy } from '../mail/service';
import type { INoteRepository } from './interfaces';
import {
  AttachmentNotFound,
  type Note,
  NoteListSchema,
  NoteNotFound,
  type NotePatch,
  type NoteRecord,
} from './structures';

const LIST_KEY = 'notes:list';
const LIST_TTL_SECONDS = 60;

class NoteLookup {
  constructor(private readonly repo: INoteRepository) {}

  require<T>(id: string, pending: Promise<T | undefined>): Result<T, NoteNotFound> {
    return Opt.fromAsync(pending.then(value => Opt.fromNative(value))).asOk(new NoteNotFound(id));
  }

  note(id: string): Result<Note, NoteNotFound> {
    return this.require(id, this.repo.get(id));
  }
}

export class NoteService {
  private readonly lookup: NoteLookup;

  constructor(
    private readonly repo: INoteRepository,
    private readonly cache: CacheService,
  ) {
    this.lookup = new NoteLookup(repo);
  }

  list(): Promise<readonly Note[]> {
    return this.cache.remember(LIST_KEY, LIST_TTL_SECONDS, NoteListSchema, async () => [...(await this.repo.list())]);
  }

  get(id: string): Result<Note, NoteNotFound> {
    return this.lookup.note(id);
  }

  async create(record: NoteRecord): Promise<Note> {
    const note = await this.repo.create(record);
    await this.cache.forget(LIST_KEY);
    return note;
  }

  update(id: string, patch: NotePatch): Result<Note, NoteNotFound> {
    return this.lookup.require(id, this.changed(this.repo.update(id, patch)));
  }

  delete(id: string): Result<string, NoteNotFound> {
    return this.lookup.require(
      id,
      this.changed(this.repo.delete(id)).then(deleted => (deleted ? id : undefined)),
    );
  }

  private async changed<T>(pending: Promise<T>): Promise<T> {
    const value = await pending;
    await this.cache.forget(LIST_KEY);
    return value;
  }
}

export class NoteShareService {
  private readonly lookup: NoteLookup;

  constructor(
    repo: INoteRepository,
    private readonly scheduler: JobScheduler,
    private readonly mail: MailPolicy,
  ) {
    this.lookup = new NoteLookup(repo);
  }

  /** Mail goes out through a job with outside effects, so a fork holds it instead of sending. */
  share(id: string, to: string): Result<Job, NoteNotFound> {
    return this.lookup
      .note(id)
      .map(note => this.scheduler.schedule(this.mail.job({ to, subject: note.title, text: note.body })));
  }
}

export class NoteAttachmentService {
  private readonly lookup: NoteLookup;

  constructor(
    repo: INoteRepository,
    private readonly files: IFileStore,
    private readonly keys: FileKeyPolicy,
    private readonly tenantId: string,
  ) {
    this.lookup = new NoteLookup(repo);
  }

  put(id: string, upload: FileUpload): Result<string, NoteNotFound> {
    return this.lookup.note(id).map(async note => {
      await this.files.put(this.key(note.id), upload);
      return note.id;
    });
  }

  get(id: string): Result<StoredFile, NoteNotFound | AttachmentNotFound> {
    return this.lookup
      .note(id)
      .mapErr<NoteNotFound | AttachmentNotFound>(error => error)
      .andThen(note =>
        this.lookup.require(note.id, this.files.get(this.key(note.id))).mapErr(() => new AttachmentNotFound(note.id)),
      );
  }

  /** Call after the note is deleted; a missing object is not an error. */
  remove(id: string): Promise<void> {
    return this.files.delete(this.key(id));
  }

  private key(noteId: string): string {
    return this.keys.noteAttachment(this.tenantId, noteId);
  }
}
