import { afterAll, beforeAll, describe, it } from 'bun:test';
import { randomUUID } from 'node:crypto';
import { expectErr, expectOk } from '@atomicloud/diene.result/test-helper';
import 'should';
import { CopyBucketForker } from '../../../src/adapters/fork/copy-bucket-forker';
import { S3Client } from '../../../src/adapters/fork/s3-client';
import { S3ForkBuckets } from '../../../src/adapters/fork/s3-fork-buckets';
import { TigrisBucketForker } from '../../../src/adapters/fork/tigris-bucket-forker';
import { ForkNaming } from '../../../src/lib/fork/naming';
import { MinioFixture } from './minio';

const PAGE_PLUS_ONE = 1001;

describe('CopyBucketForker (Testcontainers MinIO)', () => {
  let minio: MinioFixture;
  let subject: CopyBucketForker;

  beforeAll(async () => {
    minio = await MinioFixture.start();
    await minio.createBucket('files');
    await minio.createBucket('unrelated');
    await minio.put('files', 'tenants/acme/report & notes.txt', 'quarterly');
    const keys = Array.from({ length: PAGE_PLUS_ONE - 1 }, (_, i) => `bulk/${String(i).padStart(4, '0')}.txt`);
    for (let i = 0; i < keys.length; i += 50) {
      await Promise.all(keys.slice(i, i + 50).map(key => minio.put('files', key, key)));
    }
    const buckets = new S3ForkBuckets(
      new S3Client(minio.connection),
      new ForkNaming({ database: 'app', bucket: 'files' }),
    );
    subject = new CopyBucketForker(buckets);
  }, 120_000);

  afterAll(async () => {
    await minio.stop();
  });

  it('should copy every object, past one listing page, into the fork bucket', async () => {
    // Act
    const actual = await expectOk(subject.fork('demo'));

    // Assert
    actual.should.equal('files-fork-demo');
    (await minio.get('files-fork-demo', 'tenants/acme/report & notes.txt')).should.equal('quarterly');
    (await minio.get('files-fork-demo', 'bulk/0999.txt')).should.equal('bulk/0999.txt');
    const copied = await new S3Client(minio.connection).listObjects('files-fork-demo');
    copied.length.should.equal(PAGE_PLUS_ONE);
  }, 60_000);

  it('should list only forks of the source bucket', async () => {
    // Act
    const actual = await expectOk(subject.list());

    // Assert
    actual.should.deepEqual(['demo']);
  });

  it('should delete a fork bucket and its objects, leaving the source', async () => {
    // Act
    await expectOk(subject.delete('demo'));

    // Assert
    (await minio.buckets()).should.deepEqual(['files', 'unrelated']);
  }, 60_000);

  it('should report a fork bucket that does not exist', async () => {
    // Act
    const actual = await expectErr(subject.delete('ghost'));

    // Assert
    actual.should.deepEqual({ kind: 'not_found', name: 'ghost' });
  });

  it('should report a storage failure', async () => {
    // Arrange
    const broken = new CopyBucketForker(
      new S3ForkBuckets(new S3Client(minio.connection), new ForkNaming({ database: 'app', bucket: 'no-such-source' })),
    );

    // Act
    const actual = await expectErr(broken.fork('demo'));

    // Assert
    actual.kind.should.equal('provider_failed');
    (actual.kind === 'provider_failed' ? actual.message : '').should.containEql('404 NoSuchBucket');
  });

  it('should refuse a bucket name past 63 characters', async () => {
    // Arrange
    const long = new CopyBucketForker(
      new S3ForkBuckets(new S3Client(minio.connection), new ForkNaming({ database: 'app', bucket: 'b'.repeat(40) })),
    );

    // Act
    const actual = await expectErr(long.fork('abcdefghijklmnopqrstuvwx'));

    // Assert
    actual.kind.should.equal('invalid_name');
  });
});

describe('TigrisBucketForker', () => {
  const requests: { method: string; path: string; source: string | null }[] = [];
  let server: ReturnType<typeof Bun.serve>;
  let subject: TigrisBucketForker;

  beforeAll(() => {
    server = Bun.serve({
      port: 0,
      fetch(request) {
        const url = new URL(request.url);
        requests.push({
          method: request.method,
          path: url.pathname,
          source: request.headers.get('x-tigris-fork-source-bucket'),
        });
        if (request.method === 'GET' && url.pathname === '/') {
          return new Response(
            '<ListAllMyBucketsResult><Buckets><Bucket><Name>files-fork-demo</Name></Bucket></Buckets></ListAllMyBucketsResult>',
          );
        }
        if (request.method === 'GET') {
          return new Response('<ListBucketResult><IsTruncated>false</IsTruncated></ListBucketResult>');
        }
        return new Response('');
      },
    });
    const s3 = new S3Client({
      endpoint: `http://127.0.0.1:${server.port}/`,
      region: 'auto',
      accessKeyId: randomUUID(),
      secretAccessKey: randomUUID(),
    });
    subject = new TigrisBucketForker(new S3ForkBuckets(s3, new ForkNaming({ database: 'app', bucket: 'files' })));
  });

  afterAll(() => {
    server.stop(true);
  });

  it('should fork natively by naming the source bucket on CreateBucket', async () => {
    // Act
    const actual = await expectOk(subject.fork('demo'));

    // Assert
    actual.should.equal('files-fork-demo');
    requests.should.deepEqual([{ method: 'PUT', path: '/files-fork-demo', source: 'files' }]);
  });

  it('should list and delete forks through the S3 API', async () => {
    // Arrange
    requests.length = 0;

    // Act
    const listed = await expectOk(subject.list());
    await expectOk(subject.delete('demo'));

    // Assert
    listed.should.deepEqual(['demo']);
    requests
      .map(request => `${request.method} ${request.path}`)
      .should.deepEqual(['GET /', 'GET /', 'GET /files-fork-demo', 'DELETE /files-fork-demo']);
  });
});
