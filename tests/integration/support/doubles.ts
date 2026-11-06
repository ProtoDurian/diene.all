import {
  type Context,
  type ContextManager,
  type Meter,
  ROOT_CONTEXT,
  type Span,
  type Tracer,
} from '@opentelemetry/api';
import { AggregationTemporality, InMemoryMetricExporter, type PushMetricExporter } from '@opentelemetry/sdk-metrics';
import {
  BasicTracerProvider,
  InMemorySpanExporter,
  SimpleSpanProcessor,
  type SpanExporter,
} from '@opentelemetry/sdk-trace-base';
import type { Logger } from 'pino';
import type { MetricExporterFactories } from '../../../src/adapters/signals/metrics';
import type { TraceProvider, TraceProviderOptions, TraceSignalFactories } from '../../../src/adapters/signals/traces';
import type { OtlpExporterOptions } from '../../../src/lib/endpoint';

class CaptureStream {
  readonly lines: Record<string, unknown>[] = [];

  write(chunk: string): void {
    for (const line of chunk.split('\n')) if (line.trim() !== '') this.lines.push(JSON.parse(line));
  }
}

class RecordingMetricExporters implements MetricExporterFactories {
  readonly exporter = new InMemoryMetricExporter(AggregationTemporality.CUMULATIVE);
  readonly calls: string[] = [];
  readonly otlpOptions: OtlpExporterOptions[] = [];

  console(): PushMetricExporter {
    this.calls.push('console');
    return this.exporter;
  }

  otlp(options: OtlpExporterOptions): PushMetricExporter {
    this.calls.push('otlp');
    this.otlpOptions.push(options);
    return this.exporter;
  }
}

class RecordingTraceFactories implements TraceSignalFactories {
  readonly exporter = new InMemorySpanExporter();
  readonly calls: string[] = [];
  readonly providers: TraceProviderOptions[] = [];

  constructor(private readonly failures: { readonly flush?: boolean; readonly shutdown?: boolean } = {}) {}

  console(): SpanExporter {
    this.calls.push('console');
    return this.exporter;
  }

  otlp(): SpanExporter {
    this.calls.push('otlp');
    return this.exporter;
  }

  processor(exporter: SpanExporter): SimpleSpanProcessor {
    this.calls.push('processor');
    return new SimpleSpanProcessor(exporter);
  }

  provider(options: TraceProviderOptions): TraceProvider {
    this.providers.push(options);
    const provider = new BasicTracerProvider({
      resource: options.resource,
      ...(options.sampler === undefined ? {} : { sampler: options.sampler }),
      spanProcessors: [...options.spanProcessors],
    });
    const failures = this.failures;
    return {
      getTracer: (name, version) => provider.getTracer(name, version),
      forceFlush: async () => {
        if (failures.flush) throw new Error('trace flush failed');
        await provider.forceFlush();
      },
      shutdown: async () => {
        if (failures.shutdown) throw new Error('trace shutdown failed');
        await provider.shutdown();
      },
    };
  }
}

class FailingMetricExporter implements PushMetricExporter {
  export(_metrics: unknown, done: (result: { code: number; error?: Error }) => void): void {
    done({ code: 1, error: new Error('export failed') });
  }

  async forceFlush(): Promise<void> {
    throw new Error('exporter flush failed');
  }

  async shutdown(): Promise<void> {
    throw new Error('exporter shutdown failed');
  }
}

function throwingMeter(): Meter {
  const fail = () => {
    throw new Error('instrument creation failed');
  };
  return { createCounter: fail, createGauge: fail, createHistogram: fail } as unknown as Meter;
}

function scriptedTracer(
  span: Partial<Record<'end' | 'addEvent' | 'setStatus', () => unknown>>,
  startThrows = false,
): {
  tracer: Tracer;
  ends: () => number;
} {
  let ends = 0;
  const handle = {
    addEvent: span.addEvent ?? (() => handle),
    setStatus: span.setStatus ?? (() => handle),
    end: () => {
      ends += 1;
      span.end?.();
    },
  } as unknown as Span;
  const tracer = {
    startSpan: () => {
      if (startThrows) throw new Error('startSpan failed');
      return handle;
    },
  } as unknown as Tracer;
  return { tracer, ends: () => ends };
}

function throwingLogger(): Logger {
  const fail = () => {
    throw new Error('pino failed');
  };
  return { info: fail, flush: fail } as unknown as Logger;
}

export {
  CaptureStream,
  FailingMetricExporter,
  RecordingMetricExporters,
  RecordingTraceFactories,
  scriptedTracer,
  throwingLogger,
  throwingMeter,
};

class StackContextManager implements ContextManager {
  private current: Context = ROOT_CONTEXT;

  active(): Context {
    return this.current;
  }

  with<A extends unknown[], F extends (...args: A) => ReturnType<F>>(
    target: Context,
    fn: F,
    thisArg?: ThisParameterType<F>,
    ...args: A
  ): ReturnType<F> {
    const previous = this.current;
    this.current = target;
    try {
      return fn.call(thisArg, ...args);
    } finally {
      this.current = previous;
    }
  }

  bind<T>(_context: Context, target: T): T {
    return target;
  }

  enable(): this {
    return this;
  }

  disable(): this {
    return this;
  }
}

export { StackContextManager };
