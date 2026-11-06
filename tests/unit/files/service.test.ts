import { describe, it } from 'bun:test';
import { expectErr, expectOk } from '@atomicloud/diene.result/test-helper';
import 'should';
import { FileKeyPolicy, StorageSettingsParser } from '../../../src/lib/files/service';

describe('FileKeyPolicy', () => {
  it('should prefix a note attachment key with its tenant', () => {
    // Arrange
    const subject = new FileKeyPolicy();

    // Act
    const actual = subject.noteAttachment('tenant-a', 'note-1');

    // Assert
    actual.should.equal('tenants/tenant-a/notes/note-1/attachment');
  });
});

describe('StorageSettingsParser', () => {
  const env = {
    S3_ENDPOINT: 'http://127.0.0.1:9000/',
    S3_BUCKET: 'aseity',
    S3_REGION: 'auto',
    S3_ACCESS_KEY_ID: 'key',
    S3_SECRET_ACCESS_KEY: 'secret',
  };

  it('should read the storage bindings and drop a trailing slash from the endpoint', async () => {
    // Arrange
    const subject = new StorageSettingsParser();

    // Act
    const actual = await expectOk(subject.parse(env));

    // Assert
    actual.should.deepEqual({
      endpoint: 'http://127.0.0.1:9000',
      bucket: 'aseity',
      region: 'auto',
      accessKeyId: 'key',
      secretAccessKey: 'secret',
    });
  });

  it('should reject missing credentials', async () => {
    // Arrange
    const subject = new StorageSettingsParser();

    // Act
    const actual = await expectErr(subject.parse({ ...env, S3_SECRET_ACCESS_KEY: '' }));

    // Assert
    actual.issues.map(issue => issue.path.join('.')).should.deepEqual(['S3_SECRET_ACCESS_KEY']);
  });
});
