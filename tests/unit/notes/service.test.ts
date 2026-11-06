import { describe, it } from 'bun:test';
import { expectErr, expectOk } from '@atomicloud/diene.result/test-helper';
import 'should';
import type { ICacheStore } from '../../../src/lib/cache/interfaces';
import { CacheService } from '../../../src/lib/cache/service';
import type { IFileStore } from '../../../src/lib/files/interfaces';
import { FileKeyPolicy } from '../../../src/lib/files/service';
import type { FileUpload, StoredFile } from '../../../src/lib/files/structures';
import type { IJobQueue } from '../../../src/lib/jobs/interfaces';
import { JobScheduler } from '../../../src/lib/jobs/service';
import type { Job, NewJob } from '../../../src/lib/jobs/structures';
import { MailPolicy } from '../../../src/lib/mail/service';
import type { INoteRepository } from '../../../src/lib/notes/interfaces';
import { NoteAttachmentService, NoteService, NoteShareService } from '../../../src/lib/notes/service';
import {
  AttachmentNotFound,
  type Note,
  NoteNotFound,
  type NotePatch,
  type NoteRecord,
} from '../../../src/lib/notes/structures';

class MemoryNoteRepository implements INoteRepository {
  readonly notes = new Map<string, Note>();
  lists = 0;

  async list(): Promise<readonly Note[]> {
    this.lists++;
    return [...this.notes.values()];
  }

  async get(id: string): Promise<Note | undefined> {
    return this.notes.get(id);
  }

  async create(record: NoteRecord): Promise<Note> {
    const note = { id: crypto.randomUUID(), createdAt: new Date('2024-03-15T14:30:00.000Z'), ...record };
    this.notes.set(note.id, note);
    return note;
  }

  async update(id: string, patch: NotePatch): Promise<Note | undefined> {
    const current = this.notes.get(id);
    if (current === undefined) return undefined;
    const next = { ...current, ...patch };
    this.notes.set(id, next);
    return next;
  }

  async delete(id: string): Promise<boolean> {
    return this.notes.delete(id);
  }
}

class JsonCacheStore implements ICacheStore {
  readonly entries = new Map<string, string>();

  async get(key: string): Promise<unknown> {
    const raw = this.entries.get(key);
    return raw === undefined ? undefined : JSON.parse(raw);
  }

  async set(key: string, value: unknown): Promise<void> {
    this.entries.set(key, JSON.stringify(value));
  }

  async delete(key: string): Promise<void> {
    this.entries.delete(key);
  }
}

class MemoryFileStore implements IFileStore {
  readonly objects = new Map<string, FileUpload>();

  async put(key: string, upload: FileUpload): Promise<void> {
    this.objects.set(key, upload);
  }

  async get(key: string): Promise<StoredFile | undefined> {
    const upload = this.objects.get(key);
    if (upload === undefined) return undefined;
    return { body: new Blob([upload.body]).stream(), contentType: upload.contentType, size: upload.body.byteLength };
  }

  async delete(key: string): Promise<void> {
    this.objects.delete(key);
  }
}

class MemoryQueue implements IJobQueue {
  readonly jobs: Job[] = [];

  async enqueue(input: NewJob, status: 'queued' | 'held'): Promise<Job> {
    const created: Job = { ...input, id: crypto.randomUUID(), tenantId: 't', status, runAt: new Date(), attempts: 0 };
    this.jobs.push(created);
    return created;
  }
}

const notesService = () => {
  const repo = new MemoryNoteRepository();
  const cache = new JsonCacheStore();
  return { repo, cache, subject: new NoteService(repo, new CacheService(cache)) };
};

describe('NoteService', () => {
  it('should serve the list from cache until a note changes', async () => {
    // Arrange
    const { repo, subject } = notesService();
    const created = await subject.create({ title: 'First', body: 'one' });

    // Act
    const first = await subject.list();
    const second = await subject.list();

    // Assert
    repo.lists.should.equal(1);
    second.should.deepEqual(first);
    (second[0] as Note).createdAt.should.be.instanceOf(Date);
    (second[0] as Note).id.should.equal(created.id);
  });

  it('should drop the cached list when a note is created', async () => {
    // Arrange
    const { subject } = notesService();
    await subject.list();

    // Act
    await subject.create({ title: 'Second', body: 'two' });
    const actual = await subject.list();

    // Assert
    actual.map(note => note.title).should.deepEqual(['Second']);
  });

  it('should get a note by id', async () => {
    // Arrange
    const { subject } = notesService();
    const created = await subject.create({ title: 'First', body: 'one' });

    // Act
    const actual = await expectOk(subject.get(created.id));

    // Assert
    actual.should.deepEqual(created);
  });

  it('should report an unknown note as not found', async () => {
    // Arrange
    const { subject } = notesService();

    // Act
    const actual = await expectErr(subject.get('missing'));

    // Assert
    actual.should.be.instanceOf(NoteNotFound);
    actual.id.should.equal('missing');
  });

  it('should update a note and refresh the cached list', async () => {
    // Arrange
    const { subject } = notesService();
    const created = await subject.create({ title: 'First', body: 'one' });
    await subject.list();

    // Act
    const actual = await expectOk(subject.update(created.id, { body: 'changed' }));
    const listed = await subject.list();

    // Assert
    actual.body.should.equal('changed');
    (listed[0] as Note).body.should.equal('changed');
  });

  it('should report an update to an unknown note as not found', async () => {
    // Arrange
    const { subject } = notesService();

    // Act
    const actual = await expectErr(subject.update('missing', { title: 'x' }));

    // Assert
    actual.id.should.equal('missing');
  });

  it('should delete a note and return its id', async () => {
    // Arrange
    const { repo, subject } = notesService();
    const created = await subject.create({ title: 'First', body: 'one' });

    // Act
    const actual = await expectOk(subject.delete(created.id));

    // Assert
    actual.should.equal(created.id);
    repo.notes.size.should.equal(0);
  });

  it('should report a delete of an unknown note as not found', async () => {
    // Arrange
    const { subject } = notesService();

    // Act
    const actual = await expectErr(subject.delete('missing'));

    // Assert
    actual.id.should.equal('missing');
  });
});

describe('NoteShareService', () => {
  it.each([
    { isFork: false, expected: 'queued' },
    { isFork: true, expected: 'held' },
  ])('should schedule the note as a mail job ($expected when fork=$isFork)', async ({ isFork, expected }) => {
    // Arrange
    const repo = new MemoryNoteRepository();
    const note = await repo.create({ title: 'Plan', body: 'Ship it' });
    const queue = new MemoryQueue();
    const subject = new NoteShareService(repo, new JobScheduler(queue, isFork), new MailPolicy());

    // Act
    const actual = await expectOk(subject.share(note.id, 'b@example.com'));

    // Assert
    actual.status.should.equal(expected);
    actual.outsideEffect.should.be.true();
    actual.payload.should.deepEqual({ to: 'b@example.com', subject: 'Plan', text: 'Ship it' });
  });

  it('should not schedule mail for an unknown note', async () => {
    // Arrange
    const queue = new MemoryQueue();
    const subject = new NoteShareService(new MemoryNoteRepository(), new JobScheduler(queue, false), new MailPolicy());

    // Act
    const actual = await expectErr(subject.share('missing', 'b@example.com'));

    // Assert
    actual.id.should.equal('missing');
    queue.jobs.should.have.length(0);
  });
});

describe('NoteAttachmentService', () => {
  const setup = async () => {
    const repo = new MemoryNoteRepository();
    const files = new MemoryFileStore();
    const note = await repo.create({ title: 'Doc', body: 'with file' });
    return { note, files, subject: new NoteAttachmentService(repo, files, new FileKeyPolicy(), 'tenant-a') };
  };

  it('should store an attachment under the tenant key and read it back', async () => {
    // Arrange
    const { note, files, subject } = await setup();
    const body = new TextEncoder().encode('hello').buffer as ArrayBuffer;

    // Act
    const stored = await expectOk(subject.put(note.id, { body, contentType: 'text/plain' }));
    const actual = await expectOk(subject.get(note.id));

    // Assert
    stored.should.equal(note.id);
    [...files.objects.keys()].should.deepEqual([`tenants/tenant-a/notes/${note.id}/attachment`]);
    actual.contentType.should.equal('text/plain');
    (await new Response(actual.body).text()).should.equal('hello');
  });

  it('should refuse an attachment for an unknown note', async () => {
    // Arrange
    const { files, subject } = await setup();

    // Act
    const actual = await expectErr(subject.put('missing', { body: new ArrayBuffer(1), contentType: 'text/plain' }));

    // Assert
    actual.should.be.instanceOf(NoteNotFound);
    files.objects.size.should.equal(0);
  });

  it('should tell a missing note apart from a missing attachment', async () => {
    // Arrange
    const { note, subject } = await setup();

    // Act
    const noNote = await expectErr(subject.get('missing'));
    const noFile = await expectErr(subject.get(note.id));

    // Assert
    noNote.should.be.instanceOf(NoteNotFound);
    noFile.should.be.instanceOf(AttachmentNotFound);
    noFile.id.should.equal(note.id);
  });

  it('should remove an attachment', async () => {
    // Arrange
    const { note, files, subject } = await setup();
    await expectOk(subject.put(note.id, { body: new ArrayBuffer(1), contentType: 'text/plain' }));

    // Act
    await subject.remove(note.id);

    // Assert
    files.objects.size.should.equal(0);
  });
});
