import { z } from 'zod';

export const MAX_TTL_SECONDS = 365 * 24 * 60 * 60;

export const MAX_SEED_COUNT = 10_000;

/** Decimal digits only — `Number()` alone would accept hex/exponential the error text excludes. */
export const TtlSchema = z.string().regex(/^\d+$/).transform(Number).pipe(z.number().int().min(1).max(MAX_TTL_SECONDS));

export const CountSchema = z
  .string()
  .regex(/^\d+$/)
  .transform(Number)
  .pipe(z.number().int().min(1).max(MAX_SEED_COUNT));
