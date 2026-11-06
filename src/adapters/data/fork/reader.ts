import type { IDatabase, IForkMarkerReader } from '../../../lib/db/interfaces';
import type { ForkMarker } from '../../../lib/db/structures';

interface ForkRow extends Record<string, unknown> {
  readonly is_fork: boolean;
  readonly source: string | null;
  readonly forked_at: Date | null;
}

export class PgForkMarkerReader implements IForkMarkerReader {
  constructor(private readonly db: IDatabase) {}

  async read(): Promise<ForkMarker> {
    const rows = await this.db.withSystem(sql =>
      sql.query<ForkRow>('SELECT is_fork, source, forked_at FROM fork_meta WHERE singleton'),
    );
    const row = rows[0];
    if (row === undefined) return { isFork: false };
    return {
      isFork: row.is_fork,
      ...(row.source === null ? {} : { source: row.source }),
      ...(row.forked_at === null ? {} : { forkedAt: row.forked_at }),
    };
  }
}

export class CachedForkMarkerReader implements IForkMarkerReader {
  private marker: Promise<ForkMarker> | undefined;

  constructor(private readonly inner: IForkMarkerReader) {}

  read(): Promise<ForkMarker> {
    this.marker ??= this.inner.read();
    return this.marker;
  }
}
