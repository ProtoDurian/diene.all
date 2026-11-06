import { Err, Ok, type Result } from '@atomicloud/diene.result';
import { z } from 'zod';
import type { StorageSettings } from './structures';

export class FileKeyPolicy {
  constructor(private readonly root = 'tenants') {}

  noteAttachment(tenantId: string, noteId: string): string {
    return `${this.root}/${tenantId}/notes/${noteId}/attachment`;
  }
}

const StorageEnvSchema = z.object({
  S3_ENDPOINT: z.url(),
  S3_BUCKET: z.string().min(1),
  S3_REGION: z.string().min(1),
  S3_ACCESS_KEY_ID: z.string().min(1),
  S3_SECRET_ACCESS_KEY: z.string().min(1),
});

export class StorageSettingsParser {
  constructor(private readonly schema: typeof StorageEnvSchema = StorageEnvSchema) {}

  parse(env: Readonly<Record<string, unknown>>): Result<StorageSettings, z.ZodError> {
    const parsed = this.schema.safeParse(env);
    if (!parsed.success) return Err(parsed.error);
    return Ok({
      endpoint: parsed.data.S3_ENDPOINT.replace(/\/+$/, ''),
      bucket: parsed.data.S3_BUCKET,
      region: parsed.data.S3_REGION,
      accessKeyId: parsed.data.S3_ACCESS_KEY_ID,
      secretAccessKey: parsed.data.S3_SECRET_ACCESS_KEY,
    });
  }
}
