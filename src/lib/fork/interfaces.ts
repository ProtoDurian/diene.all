import type { Result } from '@atomicloud/diene.result';
import type { DatabaseBranch, ForkError, SanitizePlan, SanitizeReport } from './structures';

export interface DatabaseBrancher {
  create(fork: string): Result<DatabaseBranch, ForkError>;
  list(): Result<readonly string[], ForkError>;
  delete(fork: string): Result<void, ForkError>;
}

export interface BucketForker {
  fork(fork: string): Result<string, ForkError>;
  list(): Result<readonly string[], ForkError>;
  delete(fork: string): Result<void, ForkError>;
}

export interface ForkSanitizer {
  sanitize(branch: DatabaseBranch, plan: SanitizePlan): Result<SanitizeReport, ForkError>;
}

export interface SecretGenerator {
  generate(): string;
}
