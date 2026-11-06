import type { IDatabase, ISqlExecutor } from '../../../lib/db/interfaces';
import type { IJobQueue, IJobStore } from '../../../lib/jobs/interfaces';
import type { Job, JobStatus, NewJob } from '../../../lib/jobs/structures';

interface JobRow extends Record<string, unknown> {
  readonly id: string;
  readonly tenant_id: string;
  readonly kind: string;
  readonly payload: Record<string, unknown>;
  readonly status: JobStatus;
  readonly outside_effect: boolean;
  readonly run_at: Date;
  readonly attempts: number;
  readonly locked_until: Date | null;
  readonly last_error: string | null;
}

const JOB_COLUMNS = 'id, tenant_id, kind, payload, status, outside_effect, run_at, attempts, locked_until, last_error';

class JobRowMapper {
  constructor(readonly columns: string = JOB_COLUMNS) {}

  toJob(row: JobRow): Job {
    return {
      id: row.id,
      tenantId: row.tenant_id,
      kind: row.kind,
      payload: row.payload,
      status: row.status,
      outsideEffect: row.outside_effect,
      runAt: row.run_at,
      attempts: row.attempts,
      ...(row.locked_until === null ? {} : { lockedUntil: row.locked_until }),
      ...(row.last_error === null ? {} : { lastError: row.last_error }),
    };
  }
}

export class PgJobQueue implements IJobQueue {
  private readonly mapper = new JobRowMapper();

  constructor(private readonly sql: ISqlExecutor) {}

  async enqueue(job: NewJob, status: 'queued' | 'held'): Promise<Job> {
    const rows = await this.sql.query<JobRow>(
      `INSERT INTO jobs (kind, payload, outside_effect, status) VALUES ($1, $2, $3, $4) RETURNING ${this.mapper.columns}`,
      [job.kind, JSON.stringify(job.payload), job.outsideEffect, status],
    );
    return this.mapper.toJob(rows[0] as JobRow);
  }
}

export class PgJobStore implements IJobStore {
  private readonly mapper = new JobRowMapper();
  private readonly claimSql = `
WITH next AS (
  SELECT id AS next_id FROM jobs
  WHERE run_at <= now()
    AND (status = 'queued' OR (status = 'running' AND locked_until < now()))
  ORDER BY run_at, id
  LIMIT $1
  FOR UPDATE SKIP LOCKED
)
UPDATE jobs
SET status = 'running', attempts = jobs.attempts + 1, locked_until = now() + make_interval(secs => $2)
FROM next
WHERE id = next.next_id
RETURNING ${this.mapper.columns}`;

  constructor(private readonly db: IDatabase) {}

  claim(limit: number, leaseSeconds: number): Promise<readonly Job[]> {
    return this.db.withSystem(async sql => {
      const rows = await sql.query<JobRow>(this.claimSql, [limit, leaseSeconds]);
      return rows.map(row => this.mapper.toJob(row));
    });
  }

  complete(id: string): Promise<void> {
    return this.settle("status = 'done', locked_until = NULL, last_error = NULL", [id]);
  }

  retry(id: string, delaySeconds: number, error: string): Promise<void> {
    return this.settle(
      "status = 'queued', locked_until = NULL, last_error = $3, run_at = now() + make_interval(secs => $2)",
      [id, delaySeconds, error],
    );
  }

  fail(id: string, error: string): Promise<void> {
    return this.settle("status = 'failed', locked_until = NULL, last_error = $2", [id, error]);
  }

  hold(id: string): Promise<void> {
    return this.settle("status = 'held', locked_until = NULL", [id]);
  }

  private async settle(assignments: string, params: readonly unknown[]): Promise<void> {
    await this.db.withSystem(sql => sql.query(`UPDATE jobs SET ${assignments} WHERE id = $1`, params));
  }
}
