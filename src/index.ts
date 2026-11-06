import type { ExecutionContext, ScheduledController } from '@cloudflare/workers-types';
import type { IdentityGate, RouteModule } from './adapters/api/env';
import { type AuthProvider, type RuntimeScope, WorkerRuntime, type WorkerEnv } from './adapters/api/runtime';
import { AuthModule } from './adapters/auth/module';
import { AuthSettingsParser } from './lib/auth/settings';

class BetterAuthProvider implements AuthProvider {
  async create(scope: RuntimeScope): Promise<{ gate: IdentityGate; modules: readonly RouteModule[] }> {
    const settings = await new AuthSettingsParser().parse(scope.env).unwrap();
    const module = new AuthModule({
      db: scope.db,
      settings,
      mailer: scope.mailer,
      registry: scope.registry,
      notes: scope.notes,
    });
    return { gate: module.gate.handler, modules: [module.routes, module.mcp] };
  }
}

const runtime = new WorkerRuntime(new BetterAuthProvider());

export default {
  fetch(request: Request, env: WorkerEnv, ctx: ExecutionContext): Promise<Response> {
    return runtime.fetch(request, env, ctx);
  },
  scheduled(_controller: ScheduledController, env: WorkerEnv, ctx: ExecutionContext): Promise<void> {
    return runtime.scheduled(env, ctx);
  },
};
