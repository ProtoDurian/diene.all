import type { Result } from '@atomicloud/diene.result';
import { Client } from 'pg';
import type { ForkSanitizer, SecretGenerator } from '../../lib/fork/interfaces';
import type { DatabaseBranch, ForkError, SanitizePlan, SanitizeReport } from '../../lib/fork/structures';
import { ProviderAttempt } from './attempt';

const DELETE_SECRET_ROWS = [
  'DELETE FROM "verification"',
  'DELETE FROM "oauthAccessToken"',
  'DELETE FROM "oauthRefreshToken"',
  'DELETE FROM "oauthClientAssertion"',
  'DELETE FROM "jwks"',
];

export class PgForkSanitizer implements ForkSanitizer {
  constructor(private readonly secrets: SecretGenerator) {}

  private readonly attempt = new ProviderAttempt('sanitize');

  sanitize(branch: DatabaseBranch, plan: SanitizePlan): Result<SanitizeReport, ForkError> {
    return this.attempt.run(async () => {
      const client = new Client({ connectionString: branch.connectionString });
      await client.connect();
      try {
        await client.query('BEGIN');
        const report = await this.run(client, plan);
        await client.query('COMMIT');
        return report;
      } catch (error) {
        await client.query('ROLLBACK');
        throw error;
      } finally {
        await client.end();
      }
    });
  }

  private async run(client: Client, plan: SanitizePlan): Promise<SanitizeReport> {
    const sessionsDeleted = await this.count(client, 'DELETE FROM "session"');
    const apiKeysDisabled = await this.count(client, 'UPDATE "apikey" SET "enabled" = false, "updatedAt" = now()');
    const secretRowsRotated = await this.rotateSecrets(client);
    const jobsHeld = await this.holdJobs(client);
    await client.query(
      `INSERT INTO fork_meta (singleton, is_fork, source, forked_at) VALUES (true, true, $1, now())
       ON CONFLICT (singleton) DO UPDATE SET is_fork = true, source = EXCLUDED.source, forked_at = EXCLUDED.forked_at`,
      [plan.source],
    );
    return { sessionsDeleted, apiKeysDisabled, jobsHeld, secretRowsRotated };
  }

  private async rotateSecrets(client: Client): Promise<number> {
    let rotated = 0;
    for (const statement of DELETE_SECRET_ROWS) rotated += await this.count(client, statement);
    rotated += await this.count(
      client,
      `UPDATE "account" SET "accessToken" = NULL, "refreshToken" = NULL, "idToken" = NULL,
         "accessTokenExpiresAt" = NULL, "refreshTokenExpiresAt" = NULL, "updatedAt" = now()
       WHERE "accessToken" IS NOT NULL OR "refreshToken" IS NOT NULL OR "idToken" IS NOT NULL`,
    );
    rotated += await this.count(client, `UPDATE "invitation" SET "status" = 'canceled' WHERE "status" = 'pending'`);
    const clients = await client.query<{ id: string }>(
      'SELECT "id" FROM "oauthClient" WHERE "clientSecret" IS NOT NULL',
    );
    for (const row of clients.rows) {
      await client.query('UPDATE "oauthClient" SET "clientSecret" = $1, "updatedAt" = now() WHERE "id" = $2', [
        this.secrets.generate(),
        row.id,
      ]);
    }
    return rotated + clients.rows.length;
  }

  // jobs forces row-level security, so only app_system's policy can see every tenant's rows.
  private async holdJobs(client: Client): Promise<number> {
    await client.query('SET LOCAL ROLE app_system');
    const held = await this.count(
      client,
      `UPDATE jobs SET status = 'held', locked_until = NULL WHERE outside_effect AND status NOT IN ('done', 'held')`,
    );
    await client.query('RESET ROLE');
    return held;
  }

  private async count(client: Client, statement: string): Promise<number> {
    return (await client.query(statement)).rowCount ?? 0;
  }
}
