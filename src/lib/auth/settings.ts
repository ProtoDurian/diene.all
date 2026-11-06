import { Err, Ok, type Result } from '@atomicloud/diene.result';
import { z } from 'zod';
import type { AuthSettings, SocialProviderSettings } from './structures';

const blank = (value: unknown) => (value === '' ? undefined : value);
const blankIsUnset = z.preprocess(blank, z.string().min(1).optional());

const AuthEnvSchema = z.object({
  APP_URL: z.url(),
  OAUTH_PROXY_URL: z.preprocess(blank, z.url().optional()),
  BETTER_AUTH_SECRET: z.string().min(32),
  TENANT_APPROVAL: z.enum(['manual', 'auto']),
  GITHUB_CLIENT_ID: blankIsUnset,
  GITHUB_CLIENT_SECRET: blankIsUnset,
  GOOGLE_CLIENT_ID: blankIsUnset,
  GOOGLE_CLIENT_SECRET: blankIsUnset,
});

export class AuthSettingsParser {
  constructor(private readonly schema: typeof AuthEnvSchema = AuthEnvSchema) {}

  parse(env: Readonly<Record<string, unknown>>): Result<AuthSettings, z.ZodError> {
    const parsed = this.schema.safeParse(env);
    if (!parsed.success) return Err(parsed.error);
    const data = parsed.data;
    const appUrl = this.trimSlash(data.APP_URL);
    const github = this.provider(data.GITHUB_CLIENT_ID, data.GITHUB_CLIENT_SECRET);
    const google = this.provider(data.GOOGLE_CLIENT_ID, data.GOOGLE_CLIENT_SECRET);
    return Ok({
      appUrl,
      proxyUrl: data.OAUTH_PROXY_URL ? this.trimSlash(data.OAUTH_PROXY_URL) : appUrl,
      secret: data.BETTER_AUTH_SECRET,
      tenantApproval: data.TENANT_APPROVAL,
      ...(github ? { github } : {}),
      ...(google ? { google } : {}),
    });
  }

  private provider(clientId?: string, clientSecret?: string): SocialProviderSettings | undefined {
    return clientId && clientSecret ? { clientId, clientSecret } : undefined;
  }

  private trimSlash(url: string): string {
    return url.replace(/\/+$/, '');
  }
}
