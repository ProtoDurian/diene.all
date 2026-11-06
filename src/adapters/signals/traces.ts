import { Err, Ok, Res, type Result } from '@atomicloud/diene.result';
import { ProxyTracerProvider, type Span, SpanStatusCode, type Tracer } from '@opentelemetry/api';
import { OTLPTraceExporter } from '@opentelemetry/exporter-trace-otlp-proto';
import type { Resource } from '@opentelemetry/resources';
import {
  BatchSpanProcessor,
  ConsoleSpanExporter,
  type Sampler,
  type SpanExporter,
  type SpanProcessor,
} from '@opentelemetry/sdk-trace-base';
import { NodeTracerProvider } from '@opentelemetry/sdk-trace-node';
import type { OtlpExporterOptions } from '../../lib/endpoint.js';
import type { ExporterSelection } from '../../lib/environment.js';
import type { OtelPlan } from '../../lib/plan.js';
import {
  TraceError,
  type TraceEmitter,
  type TraceRecord,
  TraceRecordValidator,
  type TraceStatus,
} from '../../lib/trace-seam.js';

const STATUS_CODES: Readonly<Record<TraceStatus, SpanStatusCode>> = Object.freeze({
  error: SpanStatusCode.ERROR,
  ok: SpanStatusCode.OK,
  unset: SpanStatusCode.UNSET,
});

interface TraceProvider {
  getTracer(name: string, version?: string): Tracer;
  forceFlush(): Promise<void>;
  shutdown(): Promise<void>;
}

interface TraceProviderOptions {
  readonly resource: Resource;
  readonly sampler?: Sampler;
  readonly spanProcessors: readonly SpanProcessor[];
}

interface TraceSignalFactories {
  console(): SpanExporter;
  otlp(options: OtlpExporterOptions): SpanExporter;
  processor(exporter: SpanExporter): SpanProcessor;
  provider(options: TraceProviderOptions): TraceProvider;
}

interface TraceSignal {
  readonly active: boolean;
  readonly emitter: TraceEmitter;
  readonly provider?: TraceProvider;
  readonly tracer: Tracer;
}

interface TraceSignalInput {
  readonly selection: ExporterSelection;
  readonly resource: Resource;
  readonly scope: Readonly<{ name: string; version: string }>;
  readonly settings: OtelPlan['traces'];
}

class SdkTraceSignalFactories implements TraceSignalFactories {
  // biome-ignore lint/complexity/noUselessConstructor: Bun coverage counts an implicit constructor as an uncovered function
  constructor() {}

  console(): SpanExporter {
    return new ConsoleSpanExporter();
  }

  otlp(options: OtlpExporterOptions): SpanExporter {
    return new OTLPTraceExporter(options);
  }

  processor(exporter: SpanExporter): SpanProcessor {
    return new BatchSpanProcessor(exporter);
  }

  provider(options: TraceProviderOptions): TraceProvider {
    const provider = new NodeTracerProvider({
      resource: options.resource,
      ...(options.sampler === undefined ? {} : { sampler: options.sampler }),
      spanProcessors: [...options.spanProcessors],
    });
    provider.register();
    return provider;
  }
}

class SdkTraceEmitter implements TraceEmitter {
  constructor(
    private readonly tracer: Tracer,
    private readonly provider?: TraceProvider,
    private readonly validator: TraceRecordValidator = new TraceRecordValidator(),
  ) {}

  emit(record: TraceRecord): Result<void, TraceError> {
    const checked = this.validator.record(record);
    if (!checked.ok) return Err(checked.error);
    if (this.provider === undefined) return Ok(undefined);
    let span: Span | undefined;
    let ended = false;
    try {
      const valid = checked.value;
      span = this.tracer.startSpan(valid.name, { attributes: valid.attributes });
      for (const event of valid.events ?? []) span.addEvent(event.name, event.attributes);
      if (valid.status !== undefined || valid.statusMessage !== undefined) {
        span.setStatus({
          code: STATUS_CODES[valid.status ?? 'unset'],
          ...(valid.statusMessage === undefined ? {} : { message: valid.statusMessage }),
        });
      }
      span.end();
      ended = true;
      return Ok(undefined);
    } catch (cause) {
      return Err(this.failure('emit', 'OpenTelemetry failed to emit the trace record', cause));
    } finally {
      if (!ended) this.endQuietly(span);
    }
  }

  flush(): Result<void, TraceError> {
    return Res.fromSerial<void, TraceError>(
      (async () => {
        try {
          await this.provider?.forceFlush();
          return ['ok', undefined];
        } catch (cause) {
          return ['err', this.failure('flush', 'OpenTelemetry failed to flush traces', cause)];
        }
      })(),
    );
  }

  private endQuietly(span: Span | undefined): void {
    try {
      span?.end();
    } catch {
      return;
    }
  }

  private failure(operation: string, message: string, cause: unknown): TraceError {
    return new TraceError('io', operation, message, {
      cause: cause instanceof Error ? cause.message : String(cause),
    });
  }
}

class TraceSignalFactory {
  constructor(private readonly factories: TraceSignalFactories = new SdkTraceSignalFactories()) {}

  inactive(scope: TraceSignalInput['scope']): TraceSignal {
    const tracer = new ProxyTracerProvider().getTracer(scope.name, scope.version);
    return Object.freeze({ active: false, emitter: new SdkTraceEmitter(tracer), tracer });
  }

  create(input: TraceSignalInput): TraceSignal {
    const processors = [
      ...(input.selection.console ? [this.factories.processor(this.factories.console())] : []),
      ...(input.selection.otlp ? [this.factories.processor(this.factories.otlp(input.settings.otlp))] : []),
    ];
    if (processors.length === 0) return this.inactive(input.scope);
    const provider = this.factories.provider({
      resource: input.resource,
      ...(input.settings.sampler === undefined ? {} : { sampler: input.settings.sampler }),
      spanProcessors: processors,
    });
    const tracer = provider.getTracer(input.scope.name, input.scope.version);
    return Object.freeze({ active: true, emitter: new SdkTraceEmitter(tracer, provider), provider, tracer });
  }
}

export type { TraceProvider, TraceProviderOptions, TraceSignal, TraceSignalFactories, TraceSignalInput };
export { SdkTraceEmitter, SdkTraceSignalFactories, TraceSignalFactory };
