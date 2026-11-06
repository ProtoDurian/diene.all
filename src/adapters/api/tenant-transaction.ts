import type { MiddlewareHandler } from 'hono';
import type { IDatabase } from '../../lib/db/interfaces';
import type { AppEnv } from './env';

/** Runs the rest of the request in one tenant transaction; a thrown handler error rolls it back. */
export class TenantTransaction {
  constructor(private readonly db: IDatabase) {}

  readonly handler: MiddlewareHandler<AppEnv> = async (c, next) => {
    await this.db.withTenant(c.var.identity.tenantId, async sql => {
      c.set('sql', sql);
      await next();
      // Hono turns a handler throw into a response before `next` returns, so rethrow to roll back.
      if (c.error) throw c.error;
    });
  };
}
