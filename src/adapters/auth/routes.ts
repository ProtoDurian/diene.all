import { oauthProviderAuthServerMetadata, oauthProviderOpenIdConfigMetadata } from '@better-auth/oauth-provider';
import type { Hono } from 'hono';
import type { TenantApprovalService } from '../../lib/auth/approval';
import type { TenantPrincipal } from '../../lib/auth/structures';
import { AUTH_BASE_PATH, type AseityAuth, MCP_PATH } from './better-auth';
import type { AuthProblems } from './problems';

export class AuthRoutes {
  constructor(
    private readonly auth: AseityAuth,
    private readonly approval: TenantApprovalService,
    private readonly problems: AuthProblems,
    private readonly appUrl: string,
  ) {}

  register<E extends object>(app: Hono<E>): void {
    const serverMetadata = oauthProviderAuthServerMetadata(this.auth);
    const openIdMetadata = oauthProviderOpenIdConfigMetadata(this.auth);
    app.get('/.well-known/oauth-authorization-server', c => serverMetadata(c.req.raw));
    app.get(`/.well-known/oauth-authorization-server${AUTH_BASE_PATH}`, c => serverMetadata(c.req.raw));
    app.get('/.well-known/openid-configuration', c => openIdMetadata(c.req.raw));
    app.get(`/.well-known/openid-configuration${AUTH_BASE_PATH}`, c => openIdMetadata(c.req.raw));
    app.get('/.well-known/oauth-protected-resource', c => c.json(this.protectedResource()));
    app.get(`/.well-known/oauth-protected-resource${MCP_PATH}`, c => c.json(this.protectedResource()));
    app.post('/api/admin/tenants/:id/approve', async c => this.approve(c.req.raw.headers, c.req.param('id')));
    app.on(['GET', 'POST'], `${AUTH_BASE_PATH}/*`, c => this.auth.handler(c.req.raw));
  }

  protectedResource() {
    return {
      resource: `${this.appUrl}${MCP_PATH}`,
      authorization_servers: [`${this.appUrl}${AUTH_BASE_PATH}`],
      bearer_methods_supported: ['header'],
    };
  }

  private async approve(headers: Headers, tenantId: string): Promise<Response> {
    const found = await this.auth.api.getSession({ headers });
    if (!found) return this.problems.unauthenticatedResponse();
    const actor = found.user.role ? { userId: found.user.id, role: found.user.role } : { userId: found.user.id };
    return this.approval.approve(actor, tenantId).match({
      ok: tenant => Response.json(this.toWire(tenant)),
      err: error => this.problems.approval(error),
    });
  }

  private toWire(tenant: TenantPrincipal) {
    const { slug, status, createdAt, approvedAt } = tenant.record;
    return {
      id: tenant.id,
      slug,
      status,
      createdAt: createdAt.toISOString(),
      ...(approvedAt ? { approvedAt: approvedAt.toISOString() } : {}),
    };
  }
}
