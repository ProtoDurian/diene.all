import { afterAll, beforeAll, describe, it } from 'bun:test';
import should from 'should';
import { FileStoreError, S3FileStore } from '../../../src/adapters/storage/s3-file-store';
import { MinioFixture } from '../../support/minio';

describe('S3FileStore (Testcontainers MinIO)', () => {
  let minio: MinioFixture;
  let subject: S3FileStore;

  beforeAll(async () => {
    minio = await MinioFixture.start();
    subject = new S3FileStore(minio.settings);
  }, 120_000);

  afterAll(async () => {
    await minio?.stop();
  }, 60_000);

  it('should put an object and stream it back with its type and size', async () => {
    // Arrange
    const key = 'tenants/a/notes/n 1/attachment';
    const body = new TextEncoder().encode('hello files').buffer as ArrayBuffer;

    // Act
    await subject.put(key, { body, contentType: 'text/plain' });
    const actual = await subject.get(key);

    // Assert
    should(actual).not.be.undefined();
    const file = actual as NonNullable<typeof actual>;
    file.contentType.should.equal('text/plain');
    file.size.should.equal(11);
    (await new Response(file.body).text()).should.equal('hello files');
  });

  it('should return undefined for a missing object', async () => {
    // Act
    const actual = await subject.get('tenants/a/missing');

    // Assert
    should(actual).be.undefined();
  });

  it('should delete an object', async () => {
    // Arrange
    await subject.put('tenants/a/doomed', { body: new ArrayBuffer(3), contentType: 'application/octet-stream' });

    // Act
    await subject.delete('tenants/a/doomed');
    const actual = await subject.get('tenants/a/doomed');

    // Assert
    should(actual).be.undefined();
  });

  it('should raise a storage error when the provider refuses the request', async () => {
    // Arrange
    const wrongKey = new S3FileStore({ ...minio.settings, secretAccessKey: crypto.randomUUID() });

    // Act
    const put = await wrongKey.put('k', { body: new ArrayBuffer(1), contentType: 'text/plain' }).catch(e => e);
    const get = await wrongKey.get('k').catch(e => e);
    const removed = await wrongKey.delete('k').catch(e => e);

    // Assert
    put.should.be.instanceOf(FileStoreError).and.have.properties({ operation: 'put', status: 403 });
    get.should.be.instanceOf(FileStoreError).and.have.properties({ operation: 'get', status: 403 });
    removed.should.be.instanceOf(FileStoreError).and.have.properties({ operation: 'delete', status: 403 });
  });
});
