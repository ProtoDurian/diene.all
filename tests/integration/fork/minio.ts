import { randomUUID } from 'node:crypto';
import { AwsClient } from 'aws4fetch';
import { GenericContainer, type StartedTestContainer, Wait } from 'testcontainers';
import type { S3Connection } from '../../../src/adapters/fork/s3-client';

const MINIO_IMAGE = 'pgsty/minio:RELEASE.2026-08-04T00-00-00Z';

export class MinioFixture {
  private readonly client: AwsClient;

  private constructor(
    private readonly container: StartedTestContainer,
    readonly connection: S3Connection,
  ) {
    this.client = new AwsClient({ ...connection, service: 's3', retries: 0 });
  }

  static async start(): Promise<MinioFixture> {
    const password = randomUUID();
    const container = await new GenericContainer(MINIO_IMAGE)
      .withCommand(['server', '/data'])
      .withEnvironment({ MINIO_ROOT_USER: 'aseity', MINIO_ROOT_PASSWORD: password })
      .withExposedPorts(9000)
      .withWaitStrategy(Wait.forHttp('/minio/health/ready', 9000))
      .start();
    return new MinioFixture(container, {
      endpoint: `http://${container.getHost()}:${container.getMappedPort(9000)}`,
      region: 'us-east-1',
      accessKeyId: 'aseity',
      secretAccessKey: password,
    });
  }

  async createBucket(bucket: string): Promise<void> {
    await this.send('PUT', `/${bucket}`);
  }

  async put(bucket: string, key: string, body: string): Promise<void> {
    await this.send('PUT', `/${bucket}/${this.encode(key)}`, body);
  }

  async get(bucket: string, key: string): Promise<string> {
    return this.send('GET', `/${bucket}/${this.encode(key)}`);
  }

  async buckets(): Promise<string[]> {
    const xml = await this.send('GET', '/');
    return [...xml.matchAll(/<Name>([^<]*)<\/Name>/g)].map(match => match[1] ?? '');
  }

  async stop(): Promise<void> {
    await this.container.stop();
  }

  private encode(key: string): string {
    return key.split('/').map(encodeURIComponent).join('/');
  }

  private async send(method: string, path: string, body?: string): Promise<string> {
    const response = await this.client.fetch(`${this.connection.endpoint}${path}`, { method, body });
    const text = await response.text();
    if (!response.ok) throw new Error(`MinIO ${method} ${path}: ${response.status} ${text}`);
    return text;
  }
}
