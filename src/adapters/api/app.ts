import { Hono } from 'hono';
import type { IJobKicker } from '../../lib/jobs/interfaces';
import type { AppEnv, RouteModule } from './env';
import type { ApiProblems } from './problems';

export interface ApiAppDependencies {
  readonly problems: ApiProblems;
  readonly kicker: IJobKicker;
  readonly modules: readonly RouteModule[];
  readonly log?: { error(message: string, fields: Record<string, unknown>): void };
}

export class ApiApp {
  constructor(private readonly deps: ApiAppDependencies) {}

  build(): Hono<AppEnv> {
    const { problems, kicker, modules, log = console } = this.deps;
    const app = new Hono<AppEnv>();

    // Outermost, so the kick runs after the tenant transaction committed the job.
    app.use('*', async (c, next) => {
      await next();
      if (c.get('kick') === true && c.error === undefined) kicker.kick();
    });

    for (const module of modules) module.register(app);

    app.notFound(c => problems.routeNotFound(c.req.method, c.req.path));
    app.onError((error, c) => {
      log.error('unhandled request error', { method: c.req.method, path: c.req.path, reason: String(error) });
      return problems.internalError();
    });
    return app;
  }
}
