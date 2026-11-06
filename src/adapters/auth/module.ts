import type { ProblemRegistry } from '@atomicloud/diene.problems';
import { TenantApprovalService } from '../../lib/auth/approval';
import type { IMailSender } from '../../lib/auth/interfaces';
import type { AuthSettings } from '../../lib/auth/structures';
import type { IDatabase } from '../../lib/db/interfaces';
import type { Pool } from 'pg';
import { UuidV7Generator } from '../../lib/auth/uuid';
import { McpRoutes } from '../mcp/routes';
import { type IMcpNotesReader, McpServer } from '../mcp/server';
import { AUTH_BASE_PATH, type AseityAuth, BetterAuthFactory, MCP_PATH } from './better-auth';
import { CredentialResolver } from './credentials';
import { TenantGate } from './gate';
import { AuthProblems } from './problems';
import { AuthRoutes } from './routes';
import { CryptoRandomSource, SystemClock } from './system';
import { PgMembershipRepository, PgTenantRepository } from './tenant-repo';
import { OAuthTokenVerifier } from './token-verifier';

export interface AuthModuleDependencies {
  readonly db: IDatabase & { readonly pool: Pool };
  readonly settings: AuthSettings;
  readonly mailer: IMailSender;
  readonly registry: ProblemRegistry;
  readonly notes: IMcpNotesReader;
}

export class AuthModule {
  readonly auth: AseityAuth;
  readonly approval: TenantApprovalService;
  readonly gate: TenantGate;
  readonly routes: AuthRoutes;
  readonly mcp: McpRoutes;

  constructor({ db, settings, mailer, registry, notes }: AuthModuleDependencies) {
    const clock = new SystemClock();
    const problems = new AuthProblems(registry);
    this.approval = new TenantApprovalService(
      settings.tenantApproval,
      new PgTenantRepository(db),
      new PgMembershipRepository(db),
      clock,
    );
    const ids = new UuidV7Generator(clock, new CryptoRandomSource());
    this.auth = new BetterAuthFactory().create({ pool: db.pool, settings, approval: this.approval, mailer, ids });
    const tokens = new OAuthTokenVerifier(
      { getJwks: () => this.auth.api.getJwks() },
      `${settings.appUrl}${AUTH_BASE_PATH}`,
      `${settings.appUrl}${MCP_PATH}`,
    );
    const credentials = new CredentialResolver(this.auth, tokens);
    this.gate = new TenantGate(credentials, this.approval, problems);
    this.routes = new AuthRoutes(this.auth, this.approval, problems, settings.appUrl);
    this.mcp = new McpRoutes(new McpServer(notes), credentials, tokens, this.approval, problems, settings.appUrl);
  }
}
