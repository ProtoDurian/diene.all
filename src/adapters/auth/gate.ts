import type { MiddlewareHandler } from 'hono';
import type { TenantApprovalService } from '../../lib/auth/approval';
import type { TenantIdentity } from '../../lib/auth/structures';
import type { CredentialResolver } from './credentials';
import type { AuthProblems } from './problems';

export interface TenantEnv {
  Variables: { identity: TenantIdentity };
}

export class TenantGate {
  constructor(
    private readonly credentials: CredentialResolver,
    private readonly approval: TenantApprovalService,
    private readonly problems: AuthProblems,
  ) {}

  readonly handler: MiddlewareHandler<TenantEnv> = async (c, next) => {
    const claim = await this.credentials.resolve(c.req.raw.headers);
    return this.approval.admit(claim).match<Response | undefined>({
      ok: async identity => {
        c.set('identity', identity);
        await next();
        return undefined;
      },
      err: error => this.problems.admission(error),
    });
  };
}
