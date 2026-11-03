import { z } from 'zod';
import type { RedisConfigResult, RedisEnvironment } from './structures';

const DEFAULT_REDIS_PORT = 6379;
const MIN_PORT = 1;
const MAX_PORT = 65535;

export class RedisConfigParser {
  constructor(private readonly environment: RedisEnvironment) {}

  private static blankAsUnset(value: unknown): unknown {
    return typeof value === 'string' && value.trim() === '' ? undefined : value;
  }

  private static readonly schema = z.object({
    REDIS_HOST: z.preprocess(RedisConfigParser.blankAsUnset, z.string().trim().optional()),
    REDIS_PORT: z.preprocess(
      RedisConfigParser.blankAsUnset,
      z
        .string()
        .trim()
        .regex(/^\d+$/, 'must be a whole number, for example 6379')
        .transform(Number)
        .refine(port => port >= MIN_PORT && port <= MAX_PORT, `must be between ${MIN_PORT} and ${MAX_PORT}`)
        .default(DEFAULT_REDIS_PORT),
    ),
  });

  /** A missing host disables Redis on purpose; it is not an error. */
  parse(): RedisConfigResult {
    const parsed = RedisConfigParser.schema.safeParse(this.environment);

    if (!parsed.success) {
      return {
        ok: false,
        issues: parsed.error.issues.map(issue => `${issue.path.join('.')} ${issue.message}`),
      };
    }

    const { REDIS_HOST: host, REDIS_PORT: port } = parsed.data;
    return { ok: true, connection: host === undefined ? undefined : { host, port } };
  }
}
