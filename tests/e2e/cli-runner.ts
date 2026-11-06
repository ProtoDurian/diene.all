import { resolve } from 'node:path';

const ROOT = resolve(import.meta.dir, '../..');

export interface Run {
  readonly code: number;
  readonly stdout: string;
  readonly stderr: string;
}

// Drives the real CLI entry point the way a user would.
export class CliRunner {
  constructor(private readonly env: Record<string, string>) {}

  async run(...args: string[]): Promise<Run> {
    const child = Bun.spawn(['bun', 'cli/index.ts', ...args], {
      cwd: ROOT,
      env: { PATH: process.env.PATH ?? '', HOME: process.env.HOME ?? '', ...this.env },
      stdout: 'pipe',
      stderr: 'pipe',
    });
    const [stdout, stderr, code] = await Promise.all([
      new Response(child.stdout).text(),
      new Response(child.stderr).text(),
      child.exited,
    ]);
    return { code, stdout, stderr };
  }

  async json(...args: string[]): Promise<object> {
    const result = await this.run(...args, '--json');
    if (result.code !== 0) throw new Error(`aseity ${args.join(' ')} exited ${result.code}: ${result.stderr}`);
    return JSON.parse(result.stdout) as object;
  }
}
