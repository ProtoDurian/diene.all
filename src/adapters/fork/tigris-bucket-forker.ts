import type { Result } from '@atomicloud/diene.result';
import type { BucketForker } from '../../lib/fork/interfaces';
import type { ForkError } from '../../lib/fork/structures';
import type { S3ForkBuckets } from './s3-fork-buckets';

const FORK_SOURCE_HEADER = 'X-Tigris-Fork-Source-Bucket';

export class TigrisBucketForker implements BucketForker {
  constructor(private readonly buckets: S3ForkBuckets) {}

  fork(fork: string): Result<string, ForkError> {
    return this.buckets.create(fork, (source, target) =>
      this.buckets.s3.createBucket(target, { [FORK_SOURCE_HEADER]: source }),
    );
  }

  list(): Result<readonly string[], ForkError> {
    return this.buckets.list();
  }

  delete(fork: string): Result<void, ForkError> {
    return this.buckets.delete(fork);
  }
}
