import type { Client } from 'pg';

export interface ForkSeed {
  readonly tenantId: string;
}

// One row in every table the fork sanitizer must clean, plus rows it must keep.
export class ForkSeeder {
  async seed(client: Client, tenantId: string): Promise<ForkSeed> {
    await client.query(`
      INSERT INTO "user" (id, name, email, "emailVerified") VALUES ('u1', 'Ada', 'ada@example.com', true);
      INSERT INTO "session" (id, "expiresAt", token, "updatedAt", "userId") VALUES
        ('s1', now() + interval '1 day', 'session-token-1', now(), 'u1'),
        ('s2', now() + interval '1 day', 'session-token-2', now(), 'u1');
      INSERT INTO "account" (id, "accountId", "providerId", "userId", "accessToken", "refreshToken", "idToken", "updatedAt") VALUES
        ('a1', 'gh-1', 'github', 'u1', 'gho_live', 'ghr_live', 'id-token', now()),
        ('a2', 'ada@example.com', 'credential', 'u1', NULL, NULL, NULL, now());
      INSERT INTO "verification" (id, identifier, value, "expiresAt") VALUES ('v1', 'ada@example.com', '123456', now() + interval '10 minutes');
      INSERT INTO "organization" (id, name, slug, "createdAt") VALUES ('o1', 'Acme', 'acme', now());
      INSERT INTO "invitation" (id, "organizationId", email, status, "expiresAt", "inviterId") VALUES
        ('i1', 'o1', 'bob@example.com', 'pending', now() + interval '1 day', 'u1'),
        ('i2', 'o1', 'eve@example.com', 'accepted', now() + interval '1 day', 'u1');
      INSERT INTO "apikey" (id, "configId", "referenceId", key, enabled, "createdAt", "updatedAt") VALUES
        ('k1', 'default', 'u1', 'hashed-key-1', true, now(), now()),
        ('k2', 'default', 'u1', 'hashed-key-2', NULL, now(), now());
      INSERT INTO "jwks" (id, "publicKey", "privateKey", "createdAt") VALUES ('j1', 'public', 'encrypted-private', now());
      INSERT INTO "oauthClient" (id, "clientId", "clientSecret", "redirectUris") VALUES
        ('c1', 'confidential', 'client-secret-live', '[]'::jsonb),
        ('c2', 'public-cli', NULL, '[]'::jsonb);
      INSERT INTO "oauthRefreshToken" (id, token, "clientId", "userId", "expiresAt", "createdAt", scopes) VALUES
        ('r1', 'refresh-live', 'confidential', 'u1', now() + interval '1 day', now(), '[]'::jsonb);
      INSERT INTO "oauthAccessToken" (id, token, "clientId", "userId", "expiresAt", "createdAt", scopes) VALUES
        ('t1', 'access-live', 'confidential', 'u1', now() + interval '1 hour', now(), '[]'::jsonb);
    `);
    await client.query(
      `INSERT INTO jobs (tenant_id, kind, status, outside_effect) VALUES
        ($1, 'send-mail', 'queued', true),
        ($1, 'call-webhook', 'failed', true),
        ($1, 'send-mail', 'done', true),
        ($1, 'rebuild-cache', 'queued', false)`,
      [tenantId],
    );
    return { tenantId };
  }
}
