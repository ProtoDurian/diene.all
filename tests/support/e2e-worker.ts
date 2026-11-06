import type { ExecutionContext } from '@cloudflare/workers-types';
import { WorkerRuntime, type WorkerEnv } from '../../src/adapters/api/runtime';
import { HeaderAuthProvider } from './test-auth';

const runtime = new WorkerRuntime(new HeaderAuthProvider());

export default {
  fetch(request: Request, env: WorkerEnv, ctx: ExecutionContext): Promise<Response> {
    return runtime.fetch(request, env, ctx);
  },
};
