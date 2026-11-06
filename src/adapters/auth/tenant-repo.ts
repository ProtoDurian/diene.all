import type { IMembershipRepository, ITenantRepository } from '../../lib/auth/interfaces';
import type { TenantPrincipal, TenantRecord, TenantStatus } from '../../lib/auth/structures';
import type { IDatabase } from '../../lib/db/interfaces';

type TenantRow = {
  id: string;
  slug: string;
  status: TenantStatus;
  created_at: Date;
  approved_at: Date | null;
};

const COLUMNS = 'id, slug, status, created_at, approved_at';
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export class PgTenantRepository implements ITenantRepository {
  constructor(private readonly db: IDatabase) {}

  async create(id: string, record: TenantRecord): Promise<TenantPrincipal> {
    const rows = await this.db.withSystem(sql =>
      sql.query<TenantRow>(
        `INSERT INTO tenants (id, slug, status, created_at, approved_at) VALUES ($1, $2, $3, $4, $5) RETURNING ${COLUMNS}`,
        [id, record.slug, record.status, record.createdAt, record.approvedAt ?? null],
      ),
    );
    return this.toPrincipal(rows[0] as TenantRow);
  }

  async get(id: string): Promise<TenantPrincipal | undefined> {
    if (!UUID.test(id)) return undefined;
    const rows = await this.db.withSystem(sql =>
      sql.query<TenantRow>(`SELECT ${COLUMNS} FROM tenants WHERE id = $1`, [id]),
    );
    return rows[0] ? this.toPrincipal(rows[0]) : undefined;
  }

  async approve(id: string, approvedAt: Date): Promise<TenantPrincipal | undefined> {
    if (!UUID.test(id)) return undefined;
    const rows = await this.db.withSystem(sql =>
      sql.query<TenantRow>(
        `UPDATE tenants SET status = 'approved', approved_at = COALESCE(approved_at, $2) WHERE id = $1 RETURNING ${COLUMNS}`,
        [id, approvedAt],
      ),
    );
    return rows[0] ? this.toPrincipal(rows[0]) : undefined;
  }

  private toPrincipal(row: TenantRow): TenantPrincipal {
    const record: TenantRecord = row.approved_at
      ? { slug: row.slug, status: row.status, createdAt: row.created_at, approvedAt: row.approved_at }
      : { slug: row.slug, status: row.status, createdAt: row.created_at };
    return { id: row.id, record };
  }
}

export class PgMembershipRepository implements IMembershipRepository {
  constructor(private readonly db: IDatabase) {}

  async isMember(userId: string, tenantId: string): Promise<boolean> {
    const rows = await this.db.withSystem(sql =>
      sql.query('SELECT 1 FROM member WHERE "userId" = $1 AND "organizationId" = $2 LIMIT 1', [userId, tenantId]),
    );
    return rows.length > 0;
  }
}
