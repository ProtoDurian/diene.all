import type { Hono, MiddlewareHandler } from 'hono';
import type { TenantIdentity } from '../../lib/auth/structures';
import type { ISqlExecutor } from '../../lib/db/interfaces';

export interface AppEnv {
  Variables: {
    identity: TenantIdentity;
    sql: ISqlExecutor;
    kick: boolean;
  };
}

/** Sets `identity` for an admitted caller of an approved tenant, or answers with a Problem. */
export type IdentityGate = MiddlewareHandler<{ Variables: { identity: TenantIdentity } }>;

/** A set of routes another module mounts on the app (auth, MCP). */
export interface RouteModule {
  register(app: Hono<AppEnv>): void;
}
