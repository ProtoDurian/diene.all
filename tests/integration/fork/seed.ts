import { randomUUID } from 'node:crypto';
import type { Client } from 'pg';

export interface ForkSeed {
  readonly clientSecret: string;
}

// One row in every table the fork sanitizer must clean, plus rows it must keep.
// Credential values are generated per run so no secret-shaped literal sits in the tree.
export class ForkSeeder {
  async seed(client: Client, tenantId: string): Promise<ForkSeed> {
    const value = () => randomUUID();
    const clientSecret = value();
    const rows: [string, unknown[]][] = [
      [`INSERT INTO "user" (id, name, email, "emailVerified") VALUES ('u1', 'Ada', 'ada@example.com', true)`, []],
      [
        `INSERT INTO "session" (id, "expiresAt", token, "updatedAt", "userId") VALUES
          ('s1', now() + interval '1 day', $1, now(), 'u1'), ('s2', now() + interval '1 day', $2, now(), 'u1')`,
        [value(), value()],
      ],
      [
        `INSERT INTO "account" (id, "accountId", "providerId", "userId", "accessToken", "refreshToken", "idToken", "updatedAt") VALUES
          ('a1', 'gh-1', 'github', 'u1', $1, $2, $3, now()),
          ('a2', 'ada@example.com', 'credential', 'u1', NULL, NULL, NULL, now())`,
        [value(), value(), value()],
      ],
      [
        `INSERT INTO "verification" (id, identifier, value, "expiresAt") VALUES ('v1', 'ada@example.com', $1, now() + interval '10 minutes')`,
        [value()],
      ],
      [`INSERT INTO "organization" (id, name, slug, "createdAt") VALUES ('o1', 'Acme', 'acme', now())`, []],
      [
        `INSERT INTO "invitation" (id, "organizationId", email, status, "expiresAt", "inviterId") VALUES
          ('i1', 'o1', 'bob@example.com', 'pending', now() + interval '1 day', 'u1'),
          ('i2', 'o1', 'eve@example.com', 'accepted', now() + interval '1 day', 'u1')`,
        [],
      ],
      [
        `INSERT INTO "apikey" (id, "configId", "referenceId", key, enabled, "createdAt", "updatedAt") VALUES
          ('k1', 'default', 'u1', $1, true, now(), now()), ('k2', 'default', 'u1', $2, NULL, now(), now())`,
        [value(), value()],
      ],
      [
        `INSERT INTO "jwks" (id, "publicKey", "privateKey", "createdAt") VALUES ('j1', $1, $2, now())`,
        [value(), value()],
      ],
      [
        `INSERT INTO "oauthClient" (id, "clientId", "clientSecret", "redirectUris") VALUES
          ('c1', 'confidential', $1, '[]'::jsonb), ('c2', 'public-cli', NULL, '[]'::jsonb)`,
        [clientSecret],
      ],
      [
        `INSERT INTO "oauthRefreshToken" (id, token, "clientId", "userId", "expiresAt", "createdAt", scopes) VALUES
          ('r1', $1, 'confidential', 'u1', now() + interval '1 day', now(), '[]'::jsonb)`,
        [value()],
      ],
      [
        `INSERT INTO "oauthAccessToken" (id, token, "clientId", "userId", "expiresAt", "createdAt", scopes) VALUES
          ('t1', $1, 'confidential', 'u1', now() + interval '1 hour', now(), '[]'::jsonb)`,
        [value()],
      ],
      [
        `INSERT INTO jobs (tenant_id, kind, status, outside_effect) VALUES
          ($1, 'send-mail', 'queued', true), ($1, 'call-webhook', 'failed', true),
          ($1, 'send-mail', 'done', true), ($1, 'rebuild-cache', 'queued', false)`,
        [tenantId],
      ],
    ];
    for (const [sql, params] of rows) await client.query(sql, params);
    return { clientSecret };
  }
}
