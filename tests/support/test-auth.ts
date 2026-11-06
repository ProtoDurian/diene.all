import type { IdentityGate, RouteModule } from '../../src/adapters/api/env';
import type { AuthProvider } from '../../src/adapters/api/runtime';

export const TEST_TENANT_HEADER = 'x-test-tenant';

/** Test-only stand-in for the real auth gate: trusts a header. Never wired into src/. */
export class HeaderAuthProvider implements AuthProvider {
  async create(): Promise<{ gate: IdentityGate; modules: readonly RouteModule[] }> {
    const gate: IdentityGate = async (c, next) => {
      const tenantId = c.req.header(TEST_TENANT_HEADER);
      if (tenantId === undefined) {
        return new Response(JSON.stringify({ title: 'Unauthenticated', status: 401 }), {
          status: 401,
          headers: { 'content-type': 'application/problem+json' },
        });
      }
      c.set('identity', { via: 'session', tenantId, userId: 'test-user' });
      await next();
    };
    return { gate, modules: [] };
  }
}
