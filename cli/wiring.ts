import { PgMigrator } from '../src/adapters/db/migrator';
import { CopyBucketForker } from '../src/adapters/fork/copy-bucket-forker';
import { LocalPostgresBrancher } from '../src/adapters/fork/local-postgres-brancher';
import { NeonBrancher } from '../src/adapters/fork/neon-brancher';
import { PgForkSanitizer } from '../src/adapters/fork/pg-fork-sanitizer';
import { RandomSecretGenerator } from '../src/adapters/fork/random-secret-generator';
import { S3Client } from '../src/adapters/fork/s3-client';
import { S3ForkBuckets } from '../src/adapters/fork/s3-fork-buckets';
import { TigrisBucketForker } from '../src/adapters/fork/tigris-bucket-forker';
import { ForkNaming } from '../src/lib/fork/naming';
import { ForkService } from '../src/lib/fork/service';
import type { CliConfig } from './config';

export class Wiring {
  constructor(private readonly config: CliConfig) {}

  async migrate(directory: string): Promise<readonly string[]> {
    const config = await this.config.migrate();
    return new PgMigrator({ connectionString: config('database').url }).migrate(directory);
  }

  async forkService(): Promise<ForkService> {
    const config = await this.config.fork();
    const database = config('database');
    const storage = config('storage');
    const source =
      database.provider === 'local'
        ? decodeURIComponent(new URL(database.url).pathname.slice(1))
        : database.neon.databaseName;
    const naming = new ForkNaming({ database: source, bucket: storage.bucket });
    const brancher =
      database.provider === 'local'
        ? new LocalPostgresBrancher(database.url, naming)
        : new NeonBrancher({ ...database.neon, parentBranchId: database.neon.parentBranchId || undefined }, naming);
    const buckets = new S3ForkBuckets(new S3Client(storage), naming);
    const forker = storage.provider === 'tigris' ? new TigrisBucketForker(buckets) : new CopyBucketForker(buckets);
    const secrets = new RandomSecretGenerator();
    return new ForkService(brancher, forker, new PgForkSanitizer(secrets), secrets, naming);
  }
}
