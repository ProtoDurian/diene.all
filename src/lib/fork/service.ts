import { Err, Ok, Res, type Result } from '@atomicloud/diene.result';
import type { BucketForker, DatabaseBrancher, ForkSanitizer, SecretGenerator } from './interfaces';
import type { ForkNaming } from './naming';
import type { DatabaseBranch, ForkCreated, ForkDeleted, ForkError, ForkSummary } from './structures';

export class ForkService {
  constructor(
    private readonly databases: DatabaseBrancher,
    private readonly buckets: BucketForker,
    private readonly sanitizer: ForkSanitizer,
    private readonly secrets: SecretGenerator,
    private readonly naming: ForkNaming,
  ) {}

  create(raw: string): Result<ForkCreated, ForkError> {
    return this.naming
      .validate(raw)
      .andThen(name => this.ensureAbsent(name))
      .andThen(name =>
        this.databases.create(name).andThen(database => this.undoOnErr(this.populate(name, database), name)),
      );
  }

  list(): Result<readonly ForkSummary[], ForkError> {
    return this.databases.list().andThen(databases =>
      this.buckets.list().map(buckets =>
        [...new Set([...databases, ...buckets])].sort().map(name => ({
          name,
          hasDatabase: databases.includes(name),
          hasBucket: buckets.includes(name),
        })),
      ),
    );
  }

  delete(raw: string): Result<ForkDeleted, ForkError> {
    return this.naming
      .validate(raw)
      .andThen(name => this.find(name))
      .andThen(fork => this.remove(fork));
  }

  private populate(name: string, database: DatabaseBranch): Result<ForkCreated, ForkError> {
    const authSecret = this.secrets.generate();
    return this.buckets
      .fork(name)
      .andThen(bucket =>
        this.sanitizer
          .sanitize(database, { source: this.naming.sources.database })
          .map(report => ({ name, database, bucket, authSecret, report })),
      );
  }

  // A half-made fork is worse than none: it may still hold live sessions and keys.
  private undoOnErr(result: Result<ForkCreated, ForkError>, name: string): Result<ForkCreated, ForkError> {
    return Res.async(() =>
      result.match<Result<ForkCreated, ForkError>>({
        ok: created => Ok(created),
        err: async error => {
          await this.buckets.delete(name).isOk();
          await this.databases.delete(name).isOk();
          return Err(error);
        },
      }),
    );
  }

  private ensureAbsent(name: string): Result<string, ForkError> {
    return this.list().andThen(forks =>
      forks.some(fork => fork.name === name) ? Err({ kind: 'already_exists', name }) : Ok(name),
    );
  }

  private find(name: string): Result<ForkSummary, ForkError> {
    return this.list().andThen(forks => {
      const fork = forks.find(candidate => candidate.name === name);
      return fork ? Ok(fork) : Err({ kind: 'not_found', name });
    });
  }

  private remove(fork: ForkSummary): Result<ForkDeleted, ForkError> {
    const bucket = fork.hasBucket ? this.buckets.delete(fork.name) : Ok<void, ForkError>(undefined);
    return bucket
      .andThen(() => (fork.hasDatabase ? this.databases.delete(fork.name) : Ok<void, ForkError>(undefined)))
      .map(() => ({ name: fork.name, database: fork.hasDatabase, bucket: fork.hasBucket }));
  }
}
