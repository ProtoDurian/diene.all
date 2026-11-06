import type { Note, NotePatch, NoteRecord } from './structures';

export interface INoteRepository {
  list(): Promise<readonly Note[]>;
  get(id: string): Promise<Note | undefined>;
  create(record: NoteRecord): Promise<Note>;
  update(id: string, patch: NotePatch): Promise<Note | undefined>;
  delete(id: string): Promise<boolean>;
}

export interface INotesReader {
  list(tenantId: string): Promise<readonly Note[]>;
}
