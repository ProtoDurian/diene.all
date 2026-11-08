import { Err, Ok, type Result } from '@atomicloud/diene.result';

type Checked<T, E> = { readonly ok: true; readonly value: T } | { readonly error: E; readonly ok: false };

abstract class PortPolicy {
  // Explicit so Bun coverage does not count an implicit constructor as uncovered
  protected constructor() {}

  protected accept<T>(value: T): Checked<T, never> {
    return Object.freeze({ ok: true, value });
  }

  protected reject<E>(error: E): Checked<never, E> {
    return Object.freeze({ error, ok: false });
  }

  protected toResult<T, E>(checked: Checked<T, E>): Result<T, E> {
    return checked.ok ? Ok<T, E>(checked.value) : Err<T, E>(checked.error);
  }
}

export type { Checked };
export { PortPolicy };
