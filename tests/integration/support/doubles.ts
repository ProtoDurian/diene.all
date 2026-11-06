import type { AgentOptions } from 'node:https';
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
import type { MetricTemporality, SpanBatchSettings } from '../../../src/lib/plan';

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
  readonly agents: AgentOptions[] = [];
  readonly temporalities: MetricTemporality[] = [];

  console(): PushMetricExporter {
    this.calls.push('console');
    return this.exporter;
  }

  otlp(options: OtlpExporterOptions, temporality: MetricTemporality, agent: AgentOptions): PushMetricExporter {
    this.calls.push('otlp');
    this.agents.push(agent);
    this.otlpOptions.push(options);
    this.temporalities.push(temporality);
    return this.exporter;
  }
}

class RecordingTraceFactories implements TraceSignalFactories {
  readonly exporter = new InMemorySpanExporter();
  readonly calls: string[] = [];
  readonly providers: TraceProviderOptions[] = [];
  readonly batches: SpanBatchSettings[] = [];
  readonly agents: AgentOptions[] = [];

  constructor(
    private readonly failures: { readonly flush?: boolean; readonly shutdown?: boolean } = {},
    private readonly log: string[] = [],
  ) {}

  console(): SpanExporter {
    this.calls.push('console');
    return this.exporter;
  }

  otlp(_options: OtlpExporterOptions, agent: AgentOptions): SpanExporter {
    this.calls.push('otlp');
    this.agents.push(agent);
    return this.exporter;
  }

  processor(exporter: SpanExporter, batch: SpanBatchSettings): SimpleSpanProcessor {
    this.calls.push('processor');
    this.batches.push(batch);
    return new SimpleSpanProcessor(exporter);
  }

  provider(options: TraceProviderOptions): TraceProvider {
    this.providers.push(options);
    const provider = new BasicTracerProvider({
      generalLimits: { ...options.limits.general },
      spanLimits: { ...options.limits.span },
      resource: options.resource,
      ...(options.sampler === undefined ? {} : { sampler: options.sampler }),
      spanProcessors: [...options.spanProcessors],
    });
    const { failures, log } = this;
    return {
      getTracer: (name: string, version?: string) => provider.getTracer(name, version),
      forceFlush: async () => {
        if (failures.flush) throw new Error('trace flush failed');
        await provider.forceFlush();
      },
      shutdown: async () => {
        log.push('traces shutdown');
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

async function exporterSettings(exporter: unknown): Promise<{
  url: string;
  timeoutMillis: number;
  compression: string;
  headers: Record<string, string>;
  agent: Record<string, unknown>;
}> {
  const delegate = (exporter as { _delegate: { _timeout: number; _transport: { _transport: { _parameters: never } } } })
    ._delegate;
  const parameters = delegate._transport._transport._parameters as {
    url: string;
    compression: string;
    headers: () => Promise<Record<string, string>>;
    agentFactory: (protocol: string) => Promise<{ options: Record<string, unknown> }>;
  };
  const agent = await parameters.agentFactory('https:');
  return {
    agent: agent.options,
    url: parameters.url,
    timeoutMillis: delegate._timeout,
    compression: parameters.compression,
    headers: await parameters.headers(),
  };
}

function withProcessEnv<T>(values: Record<string, string>, run: () => Promise<T>): Promise<T> {
  const saved = Object.fromEntries(Object.keys(values).map(key => [key, process.env[key]]));
  Object.assign(process.env, values);
  return run().finally(() => {
    for (const [key, value] of Object.entries(saved)) {
      if (value === undefined) delete process.env[key];
      else process.env[key] = value;
    }
  });
}

export { exporterSettings, withProcessEnv };
