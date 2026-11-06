import { AwsClient } from 'aws4fetch';
import type { IFileStore } from '../../lib/files/interfaces';
import type { FileUpload, StorageSettings, StoredFile } from '../../lib/files/structures';

export class FileStoreError extends Error {
  constructor(
    readonly operation: string,
    readonly status: number,
  ) {
    super(`object storage ${operation} failed with HTTP ${status}`);
    this.name = 'FileStoreError';
  }
}

export class S3FileStore implements IFileStore {
  private readonly client: AwsClient;

  constructor(private readonly settings: StorageSettings) {
    this.client = new AwsClient({
      accessKeyId: settings.accessKeyId,
      secretAccessKey: settings.secretAccessKey,
      region: settings.region,
      service: 's3',
    });
  }

  async put(key: string, upload: FileUpload): Promise<void> {
    const response = await this.client.fetch(this.url(key), {
      method: 'PUT',
      body: upload.body,
      headers: { 'content-type': upload.contentType },
    });
    await this.expectOk('put', response);
  }

  async get(key: string): Promise<StoredFile | undefined> {
    const response = await this.client.fetch(this.url(key), { method: 'GET' });
    if (response.status === 404) {
      await response.body?.cancel();
      return undefined;
    }
    await this.expectOk('get', response);
    return {
      body: response.body as ReadableStream<Uint8Array>,
      contentType: response.headers.get('content-type') ?? 'application/octet-stream',
      size: Number(response.headers.get('content-length') ?? 0),
    };
  }

  async delete(key: string): Promise<void> {
    const response = await this.client.fetch(this.url(key), { method: 'DELETE' });
    await this.expectOk('delete', response);
  }

  private url(key: string): string {
    const path = key.split('/').map(encodeURIComponent).join('/');
    return `${this.settings.endpoint}/${encodeURIComponent(this.settings.bucket)}/${path}`;
  }

  private async expectOk(operation: string, response: Response): Promise<void> {
    if (response.ok) {
      if (operation !== 'get') await response.body?.cancel();
      return;
    }
    await response.body?.cancel();
    throw new FileStoreError(operation, response.status);
  }
}
