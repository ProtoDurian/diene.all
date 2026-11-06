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

export type IdentityGate = MiddlewareHandler<{ Variables: { identity: TenantIdentity } }>;

export interface RouteModule {
  register(app: Hono<AppEnv>): void;
}
