import type { Note, NotePatch, NoteRecord } from './structures';

/** Bound to one tenant's transaction. */
export interface INoteRepository {
  list(): Promise<readonly Note[]>;
  get(id: string): Promise<Note | undefined>;
  create(record: NoteRecord): Promise<Note>;
  update(id: string, patch: NotePatch): Promise<Note | undefined>;
  delete(id: string): Promise<boolean>;
}

/** Opens its own tenant transaction; for callers outside a request (MCP tools). */
export interface INotesReader {
  list(tenantId: string): Promise<readonly Note[]>;
}
