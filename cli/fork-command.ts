import type { ForkService } from '../src/lib/fork/service';
import type { ForkError } from '../src/lib/fork/structures';
import type { Output } from './output';
import type { SecretFile } from './secret-file';

export class ForkCommand {
  constructor(
    private readonly service: ForkService,
    private readonly secrets: SecretFile,
    private readonly output: Output,
  ) {}

  async create(name: string, secretFile: string | undefined): Promise<number> {
    const path = secretFile ?? `.env.fork-${name}`;
    if (this.secrets.exists(path)) {
      this.output.error(`secret file ${path} already exists; pass --secret-file or remove it`, {
        kind: 'secret_file_exists',
        path,
      });
      return 2;
    }
    return this.service.create(name).match({
      ok: async created => {
        await this.secrets.write(path, created);
        const r = created.report;
        this.output.result(
          [
            `forked '${created.name}': database ${created.database.name}, bucket ${created.bucket}`,
            `signed out ${r.sessionsDeleted} session(s), disabled ${r.apiKeysDisabled} API key(s), rotated ${r.secretRowsRotated} secret row(s), held ${r.jobsHeld} job(s)`,
            `fork secrets written to ${path}`,
          ].join('\n'),
          {
            name: created.name,
            database: created.database.name,
            bucket: created.bucket,
            secretFile: path,
            sanitized: created.report,
          },
        );
        return 0;
      },
      err: error => this.fail(error),
    });
  }

  async list(): Promise<number> {
    return this.service.list().match({
      ok: forks => {
        const human = forks.length
          ? forks
              .map(fork => `${fork.name}\tdatabase=${fork.hasDatabase ? 'yes' : 'no'}\tbucket=${fork.hasBucket ? 'yes' : 'no'}`)
              .join('\n')
          : 'no forks';
        this.output.result(human, forks);
        return 0;
      },
      err: error => this.fail(error),
    });
  }

  async delete(name: string): Promise<number> {
    return this.service.delete(name).match({
      ok: deleted => {
        this.output.result(`deleted fork '${deleted.name}'`, deleted);
        return 0;
      },
      err: error => this.fail(error),
    });
  }

  private fail(error: ForkError): number {
    this.output.error(this.describe(error), error);
    return 1;
  }

  private describe(error: ForkError): string {
    switch (error.kind) {
      case 'invalid_name':
        return `fork name '${error.name}' ${error.reason}`;
      case 'already_exists':
        return `fork '${error.name}' already exists`;
      case 'not_found':
        return `fork '${error.name}' does not exist`;
      case 'provider_failed':
        return `${error.step} step failed: ${error.message}`;
    }
  }
}
