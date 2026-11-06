import type { Result } from '@atomicloud/diene.result';
import type { ForkNaming } from '../../lib/fork/naming';
import type { ForkError } from '../../lib/fork/structures';
import { ForkFailure, ProviderAttempt } from './attempt';
import type { S3Client } from './s3-client';

export class S3ForkBuckets {
  constructor(
    readonly s3: S3Client,
    readonly naming: ForkNaming,
  ) {}

  private readonly attempt = new ProviderAttempt('bucket');

  create(fork: string, work: (source: string, target: string) => Promise<void>): Result<string, ForkError> {
    return this.naming.bucketName(fork).andThen(target =>
      this.attempt.run(async () => {
        await work(this.naming.sources.bucket, target);
        return target;
      }),
    );
  }

  list(): Result<readonly string[], ForkError> {
    return this.attempt.run(async () =>
      (await this.s3.listBuckets()).flatMap(bucket => this.naming.bucketFork(bucket) ?? []),
    );
  }

  delete(fork: string): Result<void, ForkError> {
    return this.naming.bucketName(fork).andThen(bucket =>
      this.attempt.run(async () => {
        if (!(await this.s3.listBuckets()).includes(bucket)) {
          throw new ForkFailure({ kind: 'not_found', name: fork });
        }
        for (const key of await this.s3.listObjects(bucket)) await this.s3.deleteObject(bucket, key);
        await this.s3.deleteBucket(bucket);
      }),
    );
  }
}
