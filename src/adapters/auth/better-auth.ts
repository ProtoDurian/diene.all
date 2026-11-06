import { apiKey } from '@better-auth/api-key';
import { oauthProvider } from '@better-auth/oauth-provider';
import { betterAuth } from 'better-auth';
import { admin, emailOTP, jwt, oAuthProxy, organization } from 'better-auth/plugins';
import type { Pool } from 'pg';
import type { TenantApprovalService } from '../../lib/auth/approval';
import type { IMailSender } from '../../lib/auth/interfaces';
import type { AuthSettings, SocialProviderSettings } from '../../lib/auth/structures';
import type { UuidV7Generator } from '../../lib/auth/uuid';

export const AUTH_BASE_PATH = '/api/auth';
export const MCP_PATH = '/mcp';

export interface BetterAuthDependencies {
  readonly pool: Pool;
  readonly settings: AuthSettings;
  readonly approval: TenantApprovalService;
  readonly mailer: IMailSender;
  readonly ids: UuidV7Generator;
}

export class BetterAuthFactory {
  constructor(private readonly appName = 'aseity') {}

  create({ pool, settings, approval, mailer, ids }: BetterAuthDependencies) {
    const mcpResource = `${settings.appUrl}${MCP_PATH}`;
    return betterAuth({
      appName: this.appName,
      baseURL: settings.appUrl,
      basePath: AUTH_BASE_PATH,
      secret: settings.secret,
      database: pool,
      trustedOrigins: [...new Set([settings.appUrl, settings.proxyUrl])],
      telemetry: { enabled: false },
      // The OAuth provider issues tokens at /oauth2/token; the JWT plugin's own /token stays off.
      disabledPaths: ['/token'],
      advanced: { database: { generateId: () => ids.next() } },
      socialProviders: {
        ...this.social('github', settings.github, settings.proxyUrl),
        ...this.social('google', settings.google, settings.proxyUrl),
      },
      plugins: [
        admin(),
        organization({
          organizationHooks: {
            afterCreateOrganization: async ({ organization: created }) => {
              await approval.register({ id: created.id, slug: created.slug });
            },
          },
        }),
        emailOTP({
          sendVerificationOTP: async ({ email, otp }) => {
            await mailer.send({
              to: email,
              subject: 'Your aseity sign-in code',
              text: `Your sign-in code is ${otp}. It expires in 5 minutes.`,
            });
          },
        }),
        apiKey({ references: 'organization' }),
        oAuthProxy({ productionURL: settings.proxyUrl, currentURL: settings.appUrl }),
        jwt(),
        oauthProvider({
          loginPage: '/sign-in',
          consentPage: '/consent',
          allowDynamicClientRegistration: true,
          allowUnauthenticatedClientRegistration: true,
          resources: [mcpResource],
          clientRegistrationDefaultResources: [mcpResource],
          // Native MCP clients (CLI, desktop) register loopback callbacks without naming their type.
          clientRegistrationDefaultApplicationType: 'infer',
          postLogin: {
            page: '/select-tenant',
            consentReferenceId: ({ session }) => this.activeTenant(session),
            shouldRedirect: ({ session }) => this.activeTenant(session) === undefined,
          },
          customAccessTokenClaims: ({ referenceId }) => (referenceId ? { tenant_id: referenceId } : {}),
        }),
      ],
    });
  }

  private activeTenant(session: Record<string, unknown>): string | undefined {
    const active = session.activeOrganizationId;
    return typeof active === 'string' && active.length > 0 ? active : undefined;
  }

  private social(name: 'github' | 'google', provider: SocialProviderSettings | undefined, proxyUrl: string) {
    if (!provider) return {};
    return {
      [name]: {
        clientId: provider.clientId,
        clientSecret: provider.clientSecret,
        redirectURI: `${proxyUrl}${AUTH_BASE_PATH}/callback/${name}`,
      },
    };
  }
}

export type AseityAuth = ReturnType<BetterAuthFactory['create']>;
