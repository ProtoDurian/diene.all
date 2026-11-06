import { mkdir, mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import type { Subprocess } from 'bun';

const REPOSITORY_ROOT = resolve(import.meta.dir, '../..');

export interface WranglerDevOptions {
  readonly entry?: string;
  readonly connectionString: string;
  readonly vars: Readonly<Record<string, string>>;
}

/** Runs the Worker in local workerd through `wrangler dev`, the way a developer does. */
export class WranglerDev {
  private constructor(
    private readonly process: Subprocess<'ignore', 'pipe', 'pipe'>,
    private readonly stateDir: string,
    readonly url: string,
    private readonly output: () => string,
  ) {}

  static async start(options: WranglerDevOptions): Promise<WranglerDev> {
    // The assets directory is the web build; an empty one is enough to serve the API.
    await mkdir(join(REPOSITORY_ROOT, 'dist/web'), { recursive: true });
    const stateDir = await mkdtemp(join(tmpdir(), 'aseity-wrangler-'));
    const port = await WranglerDev.freePort();
    const args = ['wrangler', 'dev', ...(options.entry ? [options.entry] : [])];
    args.push('--config', 'wrangler.jsonc', '--ip', '127.0.0.1', '--port', String(port));
    args.push('--persist-to', stateDir, '--show-interactive-dev-session=false', '--log-level', 'info');
    for (const [name, value] of Object.entries(options.vars)) args.push('--var', `${name}:${value}`);
    const child = Bun.spawn(args, {
      cwd: REPOSITORY_ROOT,
      stdin: 'ignore',
      stdout: 'pipe',
      stderr: 'pipe',
      env: {
        ...process.env,
        CI: '1',
        WRANGLER_SEND_METRICS: 'false',
        CLOUDFLARE_HYPERDRIVE_LOCAL_CONNECTION_STRING_HYPERDRIVE: options.connectionString,
      },
    });
    let log = '';
    for (const stream of [child.stdout, child.stderr]) {
      void (async () => {
        for await (const chunk of stream) log += new TextDecoder().decode(chunk);
      })();
    }
    const dev = new WranglerDev(child, stateDir, `http://127.0.0.1:${port}`, () => log);
    await dev.ready();
    return dev;
  }

  get logs(): string {
    return this.output();
  }

  fetch(path: string, init?: RequestInit): Promise<Response> {
    return fetch(`${this.url}${path}`, init);
  }

  async stop(): Promise<void> {
    this.process.kill('SIGTERM');
    await Promise.race([this.process.exited, Bun.sleep(10_000)]);
    if (this.process.exitCode === null) this.process.kill('SIGKILL');
    await rm(this.stateDir, { recursive: true, force: true });
  }

  private async ready(): Promise<void> {
    const deadline = Date.now() + 90_000;
    while (Date.now() < deadline) {
      if (this.process.exitCode !== null) throw new Error(`wrangler dev exited early:\n${this.logs}`);
      const response = await fetch(`${this.url}/api/health`).catch(() => undefined);
      if (response !== undefined) {
        await response.body?.cancel();
        return;
      }
      await Bun.sleep(500);
    }
    throw new Error(`wrangler dev did not start in time:\n${this.logs}`);
  }

  private static async freePort(): Promise<number> {
    const server = Bun.serve({ port: 0, fetch: () => new Response() });
    const port = server.port as number;
    server.stop(true);
    return port;
  }
}
