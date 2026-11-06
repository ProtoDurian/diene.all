import { randomBytes } from 'node:crypto';
import type { SecretGenerator } from '../../lib/fork/interfaces';

export class RandomSecretGenerator implements SecretGenerator {
  constructor(private readonly bytes = 32) {}

  generate(): string {
    return randomBytes(this.bytes).toString('base64url');
  }
}
