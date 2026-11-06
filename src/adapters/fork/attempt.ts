import { Err, Ok, Res, type Result } from '@atomicloud/diene.result';
import type { ForkError, ForkStep } from '../../lib/fork/structures';

export class ForkFailure extends Error {
  constructor(readonly error: ForkError) {
    super(error.kind);
  }
}

export class ProviderAttempt {
  constructor(private readonly step: ForkStep) {}

  run<T>(work: () => Promise<T>): Result<T, ForkError> {
    return Res.async(async () => {
      try {
        return Ok<T, ForkError>(await work());
      } catch (error) {
        if (error instanceof ForkFailure) return Err<T, ForkError>(error.error);
        const message = error instanceof Error ? error.message : String(error);
        return Err<T, ForkError>({ kind: 'provider_failed', step: this.step, message });
      }
    });
  }
}
