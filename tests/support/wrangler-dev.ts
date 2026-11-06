import { mkdir, mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import type { Subprocess } from 'bun';

const REPOSITORY_ROOT = resolve(import.meta.dir, '../..');
const READY_LINE = /Ready on (http:\/\/127\.0\.0\.1:\d+)/;

export interface WranglerDevOptions {
  readonly entry?: string;
  readonly connectionString: string;
  readonly vars: Readonly<Record<string, string>>;
}

export class WranglerDev {
  private constructor(
    private readonly process: Subprocess<'ignore', 'pipe', 'pipe'>,
    private readonly stateDir: string,
    readonly url: string,
    private readonly output: () => string,
  ) {}

  static async start(options: WranglerDevOptions): Promise<WranglerDev> {
    await mkdir(join(REPOSITORY_ROOT, 'dist/web'), { recursive: true });
    const stateDir = await mkdtemp(join(tmpdir(), 'aseity-wrangler-'));
    const name = `aseity-e2e-${crypto.randomUUID().slice(0, 8)}`;
    const args = ['wrangler', 'dev', ...(options.entry ? [options.entry] : [])];
    args.push('--config', 'wrangler.jsonc', '--name', name, '--ip', '127.0.0.1');
    // Port 0: wrangler binds free ports itself, so parallel runs never collide.
    args.push('--port', '0', '--inspector-port', '0');
    args.push('--persist-to', join(stateDir, 'state'), '--show-interactive-dev-session=false', '--log-level', 'info');
    for (const [key, value] of Object.entries(options.vars)) args.push('--var', `${key}:${value}`);
    const child = Bun.spawn(args, {
      cwd: REPOSITORY_ROOT,
      stdin: 'ignore',
      stdout: 'pipe',
      stderr: 'pipe',
      env: {
        ...process.env,
        CI: '1',
        WRANGLER_SEND_METRICS: 'false',
        WRANGLER_REGISTRY_PATH: join(stateDir, 'registry'),
        WRANGLER_LOG_PATH: join(stateDir, 'logs'),
        CLOUDFLARE_HYPERDRIVE_LOCAL_CONNECTION_STRING_HYPERDRIVE: options.connectionString,
      },
    });
    let log = '';
    for (const stream of [child.stdout, child.stderr]) {
      void (async () => {
        for await (const chunk of stream) log += new TextDecoder().decode(chunk);
      })();
    }
    try {
      const url = await WranglerDev.ready(child, () => log);
      return new WranglerDev(child, stateDir, url, () => log);
    } catch (error) {
      child.kill('SIGKILL');
      await rm(stateDir, { recursive: true, force: true });
      throw error;
    }
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

  private static async ready(child: Subprocess, logs: () => string): Promise<string> {
    const deadline = Date.now() + 120_000;
    while (Date.now() < deadline) {
      if (child.exitCode !== null) throw new Error(`wrangler dev exited early:\n${logs()}`);
      const url = READY_LINE.exec(logs())?.[1];
      if (url !== undefined) {
        const response = await fetch(`${url}/api/health`).catch(() => undefined);
        if (response !== undefined) {
          await response.body?.cancel();
          return url;
        }
      }
      await Bun.sleep(250);
    }
    throw new Error(`wrangler dev did not start in time:\n${logs()}`);
  }
}
