import type { Result } from '@atomicloud/diene.result';
import type { BucketForker } from '../../lib/fork/interfaces';
import type { ForkError } from '../../lib/fork/structures';
import type { S3ForkBuckets } from './s3-fork-buckets';

export class CopyBucketForker implements BucketForker {
  constructor(private readonly buckets: S3ForkBuckets) {}

  fork(fork: string): Result<string, ForkError> {
    return this.buckets.create(fork, async (source, target) => {
      const s3 = this.buckets.s3;
      await s3.createBucket(target);
      for (const key of await s3.listObjects(source)) await s3.copyObject(source, key, target);
    });
  }

  list(): Result<readonly string[], ForkError> {
    return this.buckets.list();
  }

  delete(fork: string): Result<void, ForkError> {
    return this.buckets.delete(fork);
  }
}
