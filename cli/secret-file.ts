import { existsSync } from 'node:fs';
import { writeFile } from 'node:fs/promises';
import type { ForkCreated } from '../src/lib/fork/structures';

export class SecretFile {
  exists(path: string): boolean {
    return existsSync(path);
  }

  async write(path: string, created: ForkCreated): Promise<void> {
    const lines = [
      `# Secrets for the aseity fork '${created.name}'. Never commit this file.`,
      `BETTER_AUTH_SECRET=${created.authSecret}`,
      `CLOUDFLARE_HYPERDRIVE_LOCAL_CONNECTION_STRING_HYPERDRIVE=${created.database.connectionString}`,
      `S3_BUCKET=${created.bucket}`,
      '',
    ];
    await writeFile(path, lines.join('\n'), { mode: 0o600, flag: 'wx' });
  }
}
