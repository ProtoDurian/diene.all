import type { Result } from '@atomicloud/diene.result';

type TraceAttributeValue = boolean | number | string;
type TraceAttributes = Readonly<Record<string, TraceAttributeValue>>;
type TraceStatus = 'error' | 'ok' | 'unset';
type TraceErrorCode = 'invalid-input' | 'io' | 'unavailable' | 'unexpected-call';
type TraceErrorDetails = Readonly<Record<string, unknown>>;

interface TraceEvent {
  readonly name: string;
  readonly attributes?: TraceAttributes;
}

interface TraceRecord {
  readonly name: string;
  readonly attributes?: TraceAttributes;
  readonly events?: readonly TraceEvent[];
  readonly status?: TraceStatus;
  readonly statusMessage?: string;
}

interface TraceEmitter {
  emit(record: TraceRecord): Result<void, TraceError>;
  flush(): Result<void, TraceError>;
}

type TraceCheck<T> = Readonly<{ ok: true; value: T }> | Readonly<{ error: TraceError; ok: false }>;

const TRACE_ERROR_BRAND = Symbol.for('AtomiCloud.Diene.Otel.TraceError');
const TRACE_STATUSES: readonly unknown[] = ['error', 'ok', 'unset'];

class TraceError extends Error {
  readonly _tag = 'TraceError' as const;
  readonly details: TraceErrorDetails;

  // The ESM and CJS builds each carry this class; the brand makes instanceof hold across them.
  static override [Symbol.hasInstance](value: unknown): boolean {
    return typeof value === 'object' && value !== null && TRACE_ERROR_BRAND in value;
  }

  constructor(
    readonly code: TraceErrorCode,
    readonly operation: string,
    message: string,
    details: TraceErrorDetails = {},
  ) {
    super(message);
    this.name = 'TraceError';
    this.details = Object.freeze({ ...details });
    Object.defineProperty(this, TRACE_ERROR_BRAND, { value: true });
  }
}

class TraceRecordValidator {
  constructor(private readonly operation = 'emit') {}

  attributes(attributes: unknown): TraceCheck<TraceAttributes | undefined> {
    if (attributes === undefined) return this.accept(undefined);
    if (
      typeof attributes !== 'object' ||
      attributes === null ||
      Array.isArray(attributes) ||
      ![Object.prototype, null].includes(Object.getPrototypeOf(attributes))
    ) {
      return this.reject('Trace attributes must be a primitive record');
    }
    const entries = Object.entries(attributes);
    if (entries.some(([key]) => key.trim() === '' || key.includes('\0'))) {
      return this.reject('Trace attribute names must be non-blank and NUL-free');
    }
    const invalid = entries.some(
      ([, value]) =>
        !['boolean', 'number', 'string'].includes(typeof value) ||
        (typeof value === 'number' && !Number.isFinite(value)),
    );
    if (invalid) return this.reject('Trace attribute values must be finite primitives');
    const sorted = entries.sort(([left], [right]) => (left < right ? -1 : 1));
    return this.accept(Object.freeze(Object.fromEntries(sorted)) as TraceAttributes);
  }

  event(event: unknown): TraceCheck<Readonly<TraceEvent>> {
    if (typeof event !== 'object' || event === null) return this.reject('Trace events must be objects');
    const candidate = event as Partial<TraceEvent>;
    if (typeof candidate.name !== 'string' || candidate.name.trim() === '') {
      return this.reject('Trace event names must not be blank');
    }
    const attributes = this.attributes(candidate.attributes);
    if (!attributes.ok) return attributes;
    return this.accept(
      Object.freeze({
        ...(attributes.value === undefined ? {} : { attributes: attributes.value }),
        name: candidate.name,
      }),
    );
  }

  record(record: unknown): TraceCheck<Readonly<TraceRecord>> {
    if (typeof record !== 'object' || record === null) return this.reject('Trace record must be an object');
    const candidate = record as Partial<TraceRecord>;
    if (typeof candidate.name !== 'string' || candidate.name.trim() === '') {
      return this.reject('Trace name must not be blank');
    }
    if (candidate.status !== undefined && !TRACE_STATUSES.includes(candidate.status)) {
      return this.reject('Trace status is invalid');
    }
    if (
      candidate.statusMessage !== undefined &&
      (typeof candidate.statusMessage !== 'string' || candidate.statusMessage.trim() === '')
    ) {
      return this.reject('Trace status message must not be blank');
    }
    const attributes = this.attributes(candidate.attributes);
    if (!attributes.ok) return attributes;
    if (candidate.events !== undefined && !Array.isArray(candidate.events)) {
      return this.reject('Trace events must be an array');
    }
    const events: Readonly<TraceEvent>[] = [];
    for (const event of candidate.events ?? []) {
      const checked = this.event(event);
      if (!checked.ok) return checked;
      events.push(checked.value);
    }
    return this.accept(
      Object.freeze({
        ...(attributes.value === undefined ? {} : { attributes: attributes.value }),
        ...(events.length === 0 ? {} : { events: Object.freeze(events) }),
        name: candidate.name,
        ...(candidate.status === undefined ? {} : { status: candidate.status }),
        ...(candidate.statusMessage === undefined ? {} : { statusMessage: candidate.statusMessage }),
      }),
    );
  }

  private accept<T>(value: T): TraceCheck<T> {
    return Object.freeze({ ok: true, value });
  }

  private reject<T>(message: string): TraceCheck<T> {
    return Object.freeze({ error: new TraceError('invalid-input', this.operation, message), ok: false });
  }
}

export type {
  TraceAttributes,
  TraceAttributeValue,
  TraceCheck,
  TraceEmitter,
  TraceErrorCode,
  TraceErrorDetails,
  TraceEvent,
  TraceRecord,
  TraceStatus,
};
export { TraceError, TraceRecordValidator };
