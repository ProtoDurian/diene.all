import type { IDatabase, ISqlExecutor } from '../../../lib/db/interfaces';
import type { INoteRepository, INotesReader } from '../../../lib/notes/interfaces';
import type { Note, NotePatch, NoteRecord } from '../../../lib/notes/structures';

interface NoteRow extends Record<string, unknown> {
  readonly id: string;
  readonly title: string;
  readonly body: string;
  readonly created_at: Date;
}

const COLUMNS = 'id, title, body, created_at';

export class PgNoteRepository implements INoteRepository {
  constructor(private readonly sql: ISqlExecutor) {}

  async list(): Promise<readonly Note[]> {
    const rows = await this.sql.query<NoteRow>(`SELECT ${COLUMNS} FROM notes ORDER BY created_at DESC, id DESC`);
    return rows.map(row => this.toNote(row));
  }

  async get(id: string): Promise<Note | undefined> {
    const rows = await this.sql.query<NoteRow>(`SELECT ${COLUMNS} FROM notes WHERE id = $1`, [id]);
    return this.first(rows);
  }

  async create(record: NoteRecord): Promise<Note> {
    const rows = await this.sql.query<NoteRow>(`INSERT INTO notes (title, body) VALUES ($1, $2) RETURNING ${COLUMNS}`, [
      record.title,
      record.body,
    ]);
    return this.toNote(rows[0] as NoteRow);
  }

  async update(id: string, patch: NotePatch): Promise<Note | undefined> {
    const rows = await this.sql.query<NoteRow>(
      `UPDATE notes SET title = COALESCE($2, title), body = COALESCE($3, body) WHERE id = $1 RETURNING ${COLUMNS}`,
      [id, patch.title ?? null, patch.body ?? null],
    );
    return this.first(rows);
  }

  async delete(id: string): Promise<boolean> {
    const rows = await this.sql.query('DELETE FROM notes WHERE id = $1 RETURNING id', [id]);
    return rows.length > 0;
  }

  private first(rows: readonly NoteRow[]): Note | undefined {
    const row = rows[0];
    return row === undefined ? undefined : this.toNote(row);
  }

  private toNote(row: NoteRow): Note {
    return { id: row.id, title: row.title, body: row.body, createdAt: row.created_at };
  }
}

export class PgNotesReader implements INotesReader {
  constructor(private readonly db: IDatabase) {}

  list(tenantId: string): Promise<readonly Note[]> {
    return this.db.withTenant(tenantId, sql => new PgNoteRepository(sql).list());
  }
}
