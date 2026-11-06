import { AwsClient } from 'aws4fetch';
import { GenericContainer, type StartedTestContainer, Wait } from 'testcontainers';
import type { StorageSettings } from '../../src/lib/files/structures';

const MINIO_IMAGE = 'pgsty/minio:RELEASE.2026-08-04T00-00-00Z';

export class MinioFixture {
  private constructor(
    private readonly container: StartedTestContainer,
    readonly settings: StorageSettings,
  ) {}

  static async start(bucket = 'aseity'): Promise<MinioFixture> {
    const password = crypto.randomUUID();
    const container = await new GenericContainer(MINIO_IMAGE)
      .withEnvironment({ MINIO_ROOT_USER: 'aseity', MINIO_ROOT_PASSWORD: password })
      .withCommand(['server', '/data'])
      .withExposedPorts(9000)
      .withWaitStrategy(Wait.forHttp('/minio/health/ready', 9000))
      .start();
    const settings: StorageSettings = {
      endpoint: `http://${container.getHost()}:${container.getMappedPort(9000)}`,
      bucket,
      region: 'us-east-1',
      accessKeyId: 'aseity',
      secretAccessKey: password,
    };
    const fixture = new MinioFixture(container, settings);
    await fixture.createBucket(bucket);
    return fixture;
  }

  get env(): Record<string, string> {
    return {
      S3_ENDPOINT: this.settings.endpoint,
      S3_BUCKET: this.settings.bucket,
      S3_REGION: this.settings.region,
      S3_ACCESS_KEY_ID: this.settings.accessKeyId,
      S3_SECRET_ACCESS_KEY: this.settings.secretAccessKey,
    };
  }

  async createBucket(bucket: string): Promise<void> {
    const response = await this.client().fetch(`${this.settings.endpoint}/${bucket}`, { method: 'PUT' });
    if (!response.ok) throw new Error(`could not create bucket ${bucket}: HTTP ${response.status}`);
  }

  async objectKeys(): Promise<string[]> {
    const response = await this.client().fetch(`${this.settings.endpoint}/${this.settings.bucket}?list-type=2`);
    const xml = await response.text();
    return [...xml.matchAll(/<Key>([^<]+)<\/Key>/g)].map(match => match[1] as string);
  }

  async stop(): Promise<void> {
    await this.container.stop();
  }

  private client(): AwsClient {
    return new AwsClient({
      accessKeyId: this.settings.accessKeyId,
      secretAccessKey: this.settings.secretAccessKey,
      region: this.settings.region,
      service: 's3',
    });
  }
}
