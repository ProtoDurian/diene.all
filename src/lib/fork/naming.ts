import { Err, Ok, type Result } from '@atomicloud/diene.result';
import type { ForkError, ForkSources } from './structures';

const FORK_NAME = /^[a-z](?:[a-z0-9-]*[a-z0-9])?$/;
const MAX_FORK_NAME = 24;
// Postgres truncates identifiers past 63 bytes, and S3 caps bucket names at 63.
const MAX_RESOURCE_NAME = 63;

export class ForkNaming {
  constructor(readonly sources: ForkSources) {}

  validate(raw: string): Result<string, ForkError> {
    if (raw.length === 0 || raw.length > MAX_FORK_NAME) {
      return this.invalid(raw, `must be 1 to ${MAX_FORK_NAME} characters`);
    }
    if (!FORK_NAME.test(raw) || raw.includes('--')) {
      return this.invalid(raw, 'must be lowercase letters, digits and single hyphens, starting with a letter');
    }
    return Ok(raw);
  }

  databaseName(fork: string): Result<string, ForkError> {
    return this.fit(fork, `${this.sources.database}_fork_${fork.replaceAll('-', '_')}`);
  }

  databaseFork(database: string): string | undefined {
    return this.strip(`${this.sources.database}_fork_`, database)?.replaceAll('_', '-');
  }

  bucketName(fork: string): Result<string, ForkError> {
    return this.fit(fork, `${this.sources.bucket}-fork-${fork}`);
  }

  bucketFork(bucket: string): string | undefined {
    return this.strip(`${this.sources.bucket}-fork-`, bucket);
  }

  branchName(fork: string): string {
    return `fork-${fork}`;
  }

  branchFork(branch: string): string | undefined {
    return this.strip('fork-', branch);
  }

  private strip(prefix: string, value: string): string | undefined {
    if (!value.startsWith(prefix) || value.length === prefix.length) return undefined;
    return value.slice(prefix.length);
  }

  private fit(fork: string, name: string): Result<string, ForkError> {
    if (name.length > MAX_RESOURCE_NAME) {
      return this.invalid(fork, `makes '${name}', longer than ${MAX_RESOURCE_NAME} characters`);
    }
    return Ok(name);
  }

  private invalid(name: string, reason: string): Result<string, ForkError> {
    return Err({ kind: 'invalid_name', name, reason });
  }
}
