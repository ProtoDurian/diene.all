import { AwsClient } from 'aws4fetch';

export interface S3Connection {
  readonly endpoint: string;
  readonly region: string;
  readonly accessKeyId: string;
  readonly secretAccessKey: string;
}

const ENTITIES: Record<string, string> = { '&amp;': '&', '&lt;': '<', '&gt;': '>', '&quot;': '"', '&apos;': "'" };

export class S3Client {
  private readonly client: AwsClient;
  private readonly endpoint: string;

  constructor(connection: S3Connection) {
    this.client = new AwsClient({
      accessKeyId: connection.accessKeyId,
      secretAccessKey: connection.secretAccessKey,
      region: connection.region,
      service: 's3',
      retries: 2,
    });
    this.endpoint = connection.endpoint.replace(/\/+$/, '');
  }

  async createBucket(bucket: string, headers: Record<string, string> = {}): Promise<void> {
    await this.send('PUT', `/${bucket}`, headers);
  }

  async deleteBucket(bucket: string): Promise<void> {
    await this.send('DELETE', `/${bucket}`);
  }

  async listBuckets(): Promise<string[]> {
    const body = await this.send('GET', '/');
    return this.values(body, 'Name');
  }

  async listObjects(bucket: string): Promise<string[]> {
    const keys: string[] = [];
    let token: string | undefined;
    do {
      const query = new URLSearchParams({ 'list-type': '2' });
      if (token) query.set('continuation-token', token);
      const body = await this.send('GET', `/${bucket}?${query}`);
      keys.push(...this.values(body, 'Key'));
      token = body.includes('<IsTruncated>true</IsTruncated>')
        ? this.values(body, 'NextContinuationToken')[0]
        : undefined;
    } while (token);
    return keys;
  }

  async copyObject(source: string, key: string, target: string): Promise<void> {
    const path = this.encodeKey(key);
    await this.send('PUT', `/${target}/${path}`, { 'x-amz-copy-source': `/${source}/${path}` });
  }

  async deleteObject(bucket: string, key: string): Promise<void> {
    await this.send('DELETE', `/${bucket}/${this.encodeKey(key)}`);
  }

  private async send(method: string, path: string, headers: Record<string, string> = {}): Promise<string> {
    const response = await this.client.fetch(`${this.endpoint}${path}`, { method, headers });
    const text = await response.text();
    if (!response.ok) {
      const code = this.values(text, 'Code')[0] ?? 'UnknownError';
      throw new Error(`S3 ${method} ${path} failed: ${response.status} ${code}`);
    }
    return text;
  }

  private encodeKey(key: string): string {
    return key.split('/').map(encodeURIComponent).join('/');
  }

  private values(xml: string, tag: string): string[] {
    return [...xml.matchAll(new RegExp(`<${tag}>([^<]*)</${tag}>`, 'g'))].map(match =>
      (match[1] ?? '').replace(/&(?:amp|lt|gt|quot|apos);/g, entity => ENTITIES[entity] ?? entity),
    );
  }
}
