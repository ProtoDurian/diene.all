import type { Hono } from 'hono';
import type { TenantApprovalService } from '../../lib/auth/approval';
import type { TenantIdentity } from '../../lib/auth/structures';
import { MCP_PATH } from '../auth/better-auth';
import type { CredentialResolver } from '../auth/credentials';
import type { AuthProblems } from '../auth/problems';
import type { OAuthTokenVerifier } from '../auth/token-verifier';
import type { McpServer } from './server';

export class McpRoutes {
  constructor(
    private readonly server: McpServer,
    private readonly credentials: CredentialResolver,
    private readonly tokens: OAuthTokenVerifier,
    private readonly approval: TenantApprovalService,
    private readonly problems: AuthProblems,
    private readonly appUrl: string,
  ) {}

  register<E extends object>(app: Hono<E>): void {
    app.post(MCP_PATH, c => this.post(c.req.raw));
    app.on(['GET', 'DELETE'], MCP_PATH, () => new Response(null, { status: 405, headers: { allow: 'POST' } }));
  }

  private async post(request: Request): Promise<Response> {
    const bearer = this.credentials.bearer(request.headers);
    const claim = bearer ? await this.tokens.verify(bearer) : undefined;
    if (!claim) return this.problems.unauthenticatedResponse({ 'www-authenticate': this.challenge() });
    return this.approval.admit(claim).match({
      ok: identity => this.dispatch(request, identity),
      err: error => this.problems.admission(error),
    });
  }

  private async dispatch(request: Request, identity: TenantIdentity): Promise<Response> {
    const body = await request.json().catch(() => undefined);
    if (body === undefined) {
      return Response.json({ jsonrpc: '2.0', id: null, error: { code: -32700, message: 'Parse error' } });
    }
    const reply = await this.server.handle(body, identity);
    return reply === undefined ? new Response(null, { status: 202 }) : Response.json(reply);
  }

  private challenge(): string {
    return `Bearer resource_metadata="${this.appUrl}/.well-known/oauth-protected-resource${MCP_PATH}"`;
  }
}
