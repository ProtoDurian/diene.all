import { oauthProviderClient } from '@better-auth/oauth-provider/client';
import { emailOTPClient, organizationClient } from 'better-auth/client/plugins';
import { createAuthClient } from 'better-auth/react';

export const authClient = createAuthClient({
  plugins: [emailOTPClient(), organizationClient(), oauthProviderClient()],
});

export function followRedirect(data: unknown): boolean {
  if (typeof data === 'object' && data !== null && 'url' in data && typeof data.url === 'string') {
    window.location.assign(data.url);
    return true;
  }
  return false;
}
