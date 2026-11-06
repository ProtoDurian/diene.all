import type { CredentialClaim } from '../../lib/auth/structures';
import type { AseityAuth } from './better-auth';
import type { OAuthTokenVerifier } from './token-verifier';

const API_KEY_HEADER = 'x-api-key';

export class CredentialResolver {
  constructor(
    private readonly auth: AseityAuth,
    private readonly tokens: OAuthTokenVerifier,
  ) {}

  async resolve(headers: Headers): Promise<CredentialClaim | undefined> {
    const key = headers.get(API_KEY_HEADER);
    if (key) return this.fromApiKey(key);
    const bearer = this.bearer(headers);
    if (bearer) return this.tokens.verify(bearer);
    return this.fromSession(headers);
  }

  bearer(headers: Headers): string | undefined {
    const match = /^Bearer\s+(\S+)$/i.exec(headers.get('authorization') ?? '');
    return match?.[1];
  }

  private async fromApiKey(key: string): Promise<CredentialClaim | undefined> {
    const result = await this.auth.api.verifyApiKey({ body: { key } });
    if (!result.valid || !result.key) return undefined;
    return { via: 'apiKey', tenantId: result.key.referenceId };
  }

  private async fromSession(headers: Headers): Promise<CredentialClaim | undefined> {
    const found = await this.auth.api.getSession({ headers });
    if (!found) return undefined;
    const tenantId = found.session.activeOrganizationId ?? undefined;
    return tenantId ? { via: 'session', userId: found.user.id, tenantId } : { via: 'session', userId: found.user.id };
  }
}
