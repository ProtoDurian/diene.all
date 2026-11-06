import { oauthProviderClient } from '@better-auth/oauth-provider/client';
import { emailOTPClient, organizationClient } from 'better-auth/client/plugins';
import { createAuthClient } from 'better-auth/react';

// oauthProviderClient forwards the signed authorize query from /sign-in and /consent,
// so an MCP or CLI login resumes after the user signs in.
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
