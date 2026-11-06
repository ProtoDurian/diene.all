import type { TelemetryAttributes } from '@atomicloud/diene.interfaces';
import { InMemoryLoggerSink, InMemoryMetricsCollector } from '@atomicloud/diene.interfaces/test-helper';
import {
  type AppIdentity,
  defaultOtelBlock,
  type OtelBlock,
  OtelBootstrap,
  type OtelEnvironmentRecord,
  type OtelExporter,
  type OtelRuntime,
  ResourceIdentityMapper,
  type TraceError,
  type TraceEmitter,
  type TraceRecord,
  TraceRecordValidator,
} from '@atomicloud/diene.otel';
import { Err, Ok, type Result } from '@atomicloud/diene.result';

interface SequencedCall {
  readonly sequence: number;
}

type TraceCall =
  | (SequencedCall & { readonly method: 'emit'; readonly record: Readonly<TraceRecord> })
  | (SequencedCall & { readonly method: 'flush' });

interface OtelHarnessRun {
  readonly runtime: OtelRuntime;
  readonly logger: InMemoryLoggerSink;
  readonly metrics: InMemoryMetricsCollector;
  readonly traces: InMemoryTraceEmitter;
}

const ASSERTION_ERROR_BRAND = Symbol.for('AtomiCloud.Diene.Otel.OtelAssertionError');

const DEFAULT_IDENTITY: AppIdentity = Object.freeze({
  landscape: 'lapras',
  platform: 'atomi',
  service: 'sample',
  module: 'api',
  version: '1.0.0',
});

class OtelAssertionError extends Error {
  static override [Symbol.hasInstance](value: unknown): boolean {
    // biome-ignore lint/complexity/noThisInStatic: this is the class instanceof was called on; subclasses keep the prototype check
    if (this !== OtelAssertionError) return Function.prototype[Symbol.hasInstance].call(this, value);
    return typeof value === 'object' && value !== null && ASSERTION_ERROR_BRAND in value;
  }

  constructor(
    readonly label: string,
    readonly expected: unknown,
    readonly actual: unknown,
    message: string,
  ) {
    super(message);
    this.name = 'OtelAssertionError';
    Object.defineProperty(this, ASSERTION_ERROR_BRAND, { value: true });
  }
}

class InMemoryTraceEmitter implements TraceEmitter {
  private readonly recordedCalls: TraceCall[] = [];
  private readonly recordedRecords: Readonly<TraceRecord>[] = [];
  private nextFailure: TraceError | undefined;
  private sequence = 0;

  constructor(private readonly validator: TraceRecordValidator = new TraceRecordValidator()) {}

  get calls(): readonly TraceCall[] {
    return this.recordedCalls.map(call =>
      call.method === 'emit' ? Object.freeze({ ...call, record: this.clone(call.record) }) : Object.freeze({ ...call }),
    );
  }

  get records(): readonly Readonly<TraceRecord>[] {
    return this.recordedRecords.map(record => this.clone(record));
  }

  failNext(error: TraceError): void {
    this.nextFailure = error;
  }

  emit(record: TraceRecord): Result<void, TraceError> {
    const checked = this.validator.record(record);
    if (!checked.ok) return Err(checked.error);
    const snapshot = this.clone(checked.value);
    this.recordedCalls.push(Object.freeze({ method: 'emit', record: snapshot, sequence: this.sequence++ }));
    const failure = this.takeFailure();
    if (failure !== undefined) return Err(failure);
    this.recordedRecords.push(snapshot);
    return Ok(undefined);
  }

  flush(): Result<void, TraceError> {
    this.recordedCalls.push(Object.freeze({ method: 'flush', sequence: this.sequence++ }));
    const failure = this.takeFailure();
    return failure === undefined ? Ok(undefined) : Err(failure);
  }

  private takeFailure(): TraceError | undefined {
    const failure = this.nextFailure;
    this.nextFailure = undefined;
    return failure;
  }

  private clone(record: Readonly<TraceRecord>): Readonly<TraceRecord> {
    return Object.freeze({
      name: record.name,
      ...(record.attributes === undefined ? {} : { attributes: Object.freeze({ ...record.attributes }) }),
      ...(record.events === undefined
        ? {}
        : {
            events: Object.freeze(
              record.events.map(event =>
                Object.freeze({
                  name: event.name,
                  ...(event.attributes === undefined ? {} : { attributes: Object.freeze({ ...event.attributes }) }),
                }),
              ),
            ),
          }),
      ...(record.status === undefined ? {} : { status: record.status }),
      ...(record.statusMessage === undefined ? {} : { statusMessage: record.statusMessage }),
    });
  }
}

class OtelAssertions {
  constructor(private readonly resources: ResourceIdentityMapper = new ResourceIdentityMapper()) {}

  traceRecords(subject: InMemoryTraceEmitter, expected: readonly TraceRecord[]): void {
    this.equal('Trace records', subject.records, expected);
  }

  traceCalls(subject: InMemoryTraceEmitter, expected: readonly TraceCall[]): void {
    this.equal('Trace calls', subject.calls, expected);
  }

  resourceAttributes(actual: TelemetryAttributes, expected: TelemetryAttributes): void {
    this.equal('Resource attributes', actual, expected);
  }

  identityResource(actual: TelemetryAttributes, identity: AppIdentity): void {
    const expected = this.resources.semantic(identity);
    const carried = Object.fromEntries(Object.keys(expected).map(key => [key, actual[key]]));
    this.equal('Identity resource attributes', carried, expected);
  }

  payload(actual: unknown, expected: unknown): void {
    this.equal('Telemetry payload', actual, expected);
  }

  private equal(label: string, actual: unknown, expected: unknown): void {
    for (const [side, value] of [
      ['Actual', actual],
      ['Expected', expected],
    ] as const) {
      const invalid = this.nonJson(value, '$');
      if (invalid !== undefined) {
        throw new OtelAssertionError(label, expected, actual, `${label}: ${side} holds a non-JSON value at ${invalid}`);
      }
    }
    const actualText = JSON.stringify(this.comparable(actual));
    const expectedText = JSON.stringify(this.comparable(expected));
    if (actualText !== expectedText) {
      throw new OtelAssertionError(
        label,
        expected,
        actual,
        `${label} mismatch\nExpected: ${expectedText}\nActual: ${actualText}`,
      );
    }
  }

  private nonJson(value: unknown, path: string): string | undefined {
    if (value === null || typeof value === 'string' || typeof value === 'boolean') return undefined;
    if (typeof value === 'number') return Number.isFinite(value) ? undefined : `${path} (${value})`;
    if (typeof value !== 'object') return `${path} (${typeof value})`;
    if (Array.isArray(value)) {
      return value.map((entry, index) => this.nonJson(entry, `${path}[${index}]`)).find(found => found !== undefined);
    }
    if (![Object.prototype, null].includes(Object.getPrototypeOf(value))) return `${path} (non-plain object)`;
    return Object.entries(value)
      .map(([key, entry]) => this.nonJson(entry, `${path}.${key}`))
      .find(found => found !== undefined);
  }

  private comparable(value: unknown): unknown {
    if (Array.isArray(value)) return value.map(entry => this.comparable(entry));
    if (typeof value !== 'object' || value === null) return value;
    return Object.fromEntries(
      Object.entries(value)
        .sort(([left], [right]) => (left < right ? -1 : 1))
        .map(([key, entry]) => [key, this.comparable(entry)]),
    );
  }
}

class OtelBlockFixtures {
  constructor(private readonly endpoint = 'http://otel-collector:4318') {}

  canonical(): OtelBlock {
    return defaultOtelBlock;
  }

  disabled(): OtelBlock {
    return this.build(defaultOtelBlock.logs.exporter, false);
  }

  console(): OtelBlock {
    return this.build({ ...defaultOtelBlock.logs.exporter, console: { enabled: true } }, true);
  }

  otlp(): OtelBlock {
    const otlp = { ...defaultOtelBlock.logs.exporter.otlp, enabled: true, endpoint: this.endpoint };
    return this.build({ ...defaultOtelBlock.logs.exporter, otlp }, true);
  }

  private build(exporter: OtelExporter, enabled: boolean): OtelBlock {
    return Object.freeze({
      logs: Object.freeze({ enabled, exporter }),
      metrics: Object.freeze({ ...defaultOtelBlock.metrics, enabled, exporter }),
      traces: Object.freeze({ ...defaultOtelBlock.traces, enabled, exporter }),
    });
  }
}

class AppIdentityBuilder {
  constructor(
    private readonly identity: AppIdentity = DEFAULT_IDENTITY,
    private readonly resources: ResourceIdentityMapper = new ResourceIdentityMapper(),
  ) {}

  with(overrides: Partial<AppIdentity>): AppIdentityBuilder {
    return new AppIdentityBuilder(Object.freeze({ ...this.identity, ...overrides }), this.resources);
  }

  build(): AppIdentity {
    return this.identity;
  }

  attributes(): TelemetryAttributes {
    return this.resources.semantic(this.identity);
  }
}

class OtelTestHarness {
  constructor(private readonly bootstrap: OtelBootstrap = new OtelBootstrap()) {}

  start(
    block: OtelBlock = defaultOtelBlock,
    identity: AppIdentity = DEFAULT_IDENTITY,
    environment: OtelEnvironmentRecord = {},
  ): OtelHarnessRun {
    const logger = new InMemoryLoggerSink();
    const metrics = new InMemoryMetricsCollector();
    const traces = new InMemoryTraceEmitter();
    const runtime = this.bootstrap.init(block, identity, {
      environment,
      seams: { logger, metrics, traces },
    });
    return Object.freeze({ runtime, logger, metrics, traces });
  }
}

export type { OtelHarnessRun, TraceCall };
export {
  AppIdentityBuilder,
  DEFAULT_IDENTITY,
  InMemoryTraceEmitter,
  OtelAssertionError,
  OtelAssertions,
  OtelBlockFixtures,
  OtelTestHarness,
};
