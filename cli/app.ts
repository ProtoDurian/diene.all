import { parseArgs } from 'node:util';
import { ConfigValidationError } from '@atomicloud/diene.config';
import type { AdminGrantService } from '../src/lib/admin/service';
import type { ForkService } from '../src/lib/fork/service';
import { AdminCommand } from './admin-command';
import { ForkCommand } from './fork-command';
import { Output, type Stream } from './output';
import { SecretFile } from './secret-file';

interface CliDependencies {
  readonly version: string;
  readonly stdout: Stream;
  readonly stderr: Stream;
  migrate(directory: string): Promise<readonly string[]>;
  forkService(): Promise<ForkService>;
  adminService(): Promise<AdminGrantService>;
}

const HELP = `Usage: aseity <command> [options]

Commands:
  migrate [--dir <path>]                       Apply SQL migrations (default db/migrations)
  fork create <name> [--secret-file <path>]    Copy the database and bucket, then sanitize the copy
  fork list                                    List forks
  fork delete <name>                           Delete a fork's database and bucket
  admin grant <email>                          Give a signed-up user the admin role (approves tenants)

Options:
  --json           Print machine-readable JSON
  -h, --help       Show this help
  -v, --version    Show the version

Environment (prefix ASEITY_, nesting with __):
  ASEITY_DATABASE__URL                         Database URL as the owner role (migrate, admin, local forks)
  ASEITY_DATABASE__PROVIDER                    local (CREATE DATABASE ... TEMPLATE) or neon
  ASEITY_DATABASE__NEON__API_KEY, __PROJECT_ID, __PARENT_BRANCH_ID, __DATABASE_NAME, __ROLE_NAME
  ASEITY_STORAGE__PROVIDER                     copy (any S3 store) or tigris (native fork)
  ASEITY_STORAGE__ENDPOINT, __REGION, __BUCKET, __ACCESS_KEY_ID, __SECRET_ACCESS_KEY

A fork signs everyone out, disables API keys, rotates stored secrets, holds jobs with
outside effects and marks itself as a fork, so its Worker never sends real email.`;

export class AseityCli {
  constructor(private readonly deps: CliDependencies) {}

  async run(argv: readonly string[]): Promise<number> {
    let parsed: ReturnType<typeof this.parse>;
    try {
      parsed = this.parse(argv);
    } catch (error) {
      return this.usage(new Output(false, this.deps.stdout, this.deps.stderr), (error as Error).message);
    }
    const { values, positionals } = parsed;
    const output = new Output(values.json === true, this.deps.stdout, this.deps.stderr);
    if (values.version) {
      output.text(this.deps.version);
      return 0;
    }
    if (values.help) {
      output.text(HELP);
      return 0;
    }
    try {
      return await this.dispatch(positionals, values, output);
    } catch (error) {
      if (error instanceof ConfigValidationError) {
        output.error(`configuration is invalid (set ASEITY_ env vars, see --help):\n  ${error.issues.join('\n  ')}`, {
          kind: 'invalid_config',
          issues: error.issues,
        });
        return 2;
      }
      output.error((error as Error).message, { kind: 'failed', message: (error as Error).message });
      return 1;
    }
  }

  private async dispatch(
    positionals: string[],
    values: { dir?: string; 'secret-file'?: string },
    output: Output,
  ): Promise<number> {
    const [command, action, name, ...rest] = positionals;
    if (command === 'migrate' && action === undefined) {
      const applied = await this.deps.migrate(values.dir ?? 'db/migrations');
      output.result(applied.length ? `applied ${applied.join(', ')}` : 'database is up to date', { applied });
      return 0;
    }
    if (command === 'admin' && action === 'grant' && name !== undefined && rest.length === 0) {
      return new AdminCommand(await this.deps.adminService(), output).grant(name);
    }
    if (command === 'fork' && rest.length === 0) {
      if (action === 'list' && name === undefined) return this.fork(output).then(fork => fork.list());
      if (action === 'create' && name !== undefined) {
        return this.fork(output).then(fork => fork.create(name, values['secret-file']));
      }
      if (action === 'delete' && name !== undefined) return this.fork(output).then(fork => fork.delete(name));
    }
    return this.usage(output, command === undefined ? 'no command given' : `unknown command: ${positionals.join(' ')}`);
  }

  private async fork(output: Output): Promise<ForkCommand> {
    return new ForkCommand(await this.deps.forkService(), new SecretFile(), output);
  }

  private usage(output: Output, message: string): number {
    output.error(`${message}\n\n${HELP}`, { kind: 'usage', message });
    return 2;
  }

  private parse(argv: readonly string[]) {
    return parseArgs({
      args: [...argv],
      allowPositionals: true,
      strict: true,
      options: {
        json: { type: 'boolean' },
        help: { type: 'boolean', short: 'h' },
        version: { type: 'boolean', short: 'v' },
        dir: { type: 'string' },
        'secret-file': { type: 'string' },
      },
    });
  }
}
