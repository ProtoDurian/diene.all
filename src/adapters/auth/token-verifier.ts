import { createLocalJWKSet, type JSONWebKeySet, jwtVerify } from 'jose';
import type { CredentialClaim } from '../../lib/auth/structures';

export interface IJwksSource {
  getJwks(): Promise<JSONWebKeySet>;
}

// Verifies OAuth access tokens against the app's own key set, so the Worker never fetches itself.
export class OAuthTokenVerifier {
  constructor(
    private readonly keys: IJwksSource,
    private readonly issuer: string,
    private readonly audience: string,
  ) {}

  async verify(token: string): Promise<CredentialClaim | undefined> {
    try {
      const jwks = createLocalJWKSet(await this.keys.getJwks());
      const { payload } = await jwtVerify(token, jwks, { issuer: this.issuer, audience: this.audience });
      if (typeof payload.sub !== 'string') return undefined;
      const tenantId = typeof payload.tenant_id === 'string' ? payload.tenant_id : undefined;
      return tenantId ? { via: 'oauth', userId: payload.sub, tenantId } : { via: 'oauth', userId: payload.sub };
    } catch {
      return undefined;
    }
  }
}
