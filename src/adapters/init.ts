import type { LoggerSink, MetricsCollector, TelemetryAttributes } from '@atomicloud/diene.interfaces';
import type { Result } from '@atomicloud/diene.result';
import type { Meter, Tracer } from '@opentelemetry/api';
import type { Resource } from '@opentelemetry/resources';
import type { DestinationStream, Logger } from 'pino';
import type { OtelEnvironmentRecord, SignalFlags } from '../lib/environment.js';
import { OtelPlanner } from '../lib/plan.js';
import type { AppIdentity } from '../lib/resource.js';
import type { OtelBlock } from '../lib/schema.js';
import type { TraceEmitter } from '../lib/trace-seam.js';
import { LoggerSignalFactory, type OTLP_LOGS_BRIDGE_STATUS } from './signals/logs.js';
import { type MetricSignal, MetricSignalFactory } from './signals/metrics.js';
import { type TraceSignal, TraceSignalFactory } from './signals/traces.js';

interface OtelSeamOverrides {
  readonly logger?: LoggerSink;
  readonly metrics?: MetricsCollector;
  readonly traces?: TraceEmitter;
}

interface OtelInitOptions {
  readonly destination?: DestinationStream;
  readonly environment?: OtelEnvironmentRecord;
  readonly seams?: OtelSeamOverrides;
}

interface OtelBootstrapCollaborators {
  readonly planner?: OtelPlanner;
  readonly logs?: LoggerSignalFactory;
  readonly metrics?: MetricSignalFactory;
  readonly traces?: TraceSignalFactory;
}

type TelemetrySignal = 'logs' | 'metrics' | 'traces';
type LifecyclePhase = 'flush' | 'shutdown';

class TelemetryLifecycleError extends Error {
  constructor(
    readonly signal: TelemetrySignal,
    readonly phase: LifecyclePhase,
    override readonly cause: unknown,
  ) {
    super(`${signal} ${phase} failed: ${cause instanceof Error ? cause.message : String(cause)}`, { cause });
    this.name = 'TelemetryLifecycleError';
  }
}

interface OtelRuntime {
  readonly active: SignalFlags;
  readonly globalRegistered: boolean;
  readonly block: OtelBlock;
  readonly identity: AppIdentity;
  readonly logger: Logger;
  readonly loggerSink: LoggerSink;
  readonly meter: Meter;
  readonly metricsCollector: MetricsCollector;
  readonly otlpLogsBridge: typeof OTLP_LOGS_BRIDGE_STATUS;
  readonly resource: Resource;
  readonly resourceAttributes: TelemetryAttributes;
  readonly traceEmitter: TraceEmitter;
  readonly tracer: Tracer;
  flush(): Promise<void>;
  shutdown(): Promise<void>;
}

type OtelSessionParts = Omit<OtelRuntime, 'flush' | 'shutdown' | 'globalRegistered'> &
  Readonly<{ metricSignal: MetricSignal; traceSignal: TraceSignal }>;

class OtelSession implements OtelRuntime {
  readonly active: SignalFlags;
  readonly globalRegistered: boolean;
  readonly block: OtelBlock;
  readonly identity: AppIdentity;
  readonly logger: Logger;
  readonly loggerSink: LoggerSink;
  readonly meter: Meter;
  readonly metricsCollector: MetricsCollector;
  readonly otlpLogsBridge: typeof OTLP_LOGS_BRIDGE_STATUS;
  readonly resource: Resource;
  readonly resourceAttributes: TelemetryAttributes;
  readonly traceEmitter: TraceEmitter;
  readonly tracer: Tracer;
  private readonly metricSignal: MetricSignal;
  private readonly traceSignal: TraceSignal;

  constructor(parts: OtelSessionParts) {
    this.active = parts.active;
    this.block = parts.block;
    this.identity = parts.identity;
    this.logger = parts.logger;
    this.loggerSink = parts.loggerSink;
    this.meter = parts.meter;
    this.metricsCollector = parts.metricsCollector;
    this.otlpLogsBridge = parts.otlpLogsBridge;
    this.resource = parts.resource;
    this.resourceAttributes = parts.resourceAttributes;
    this.traceEmitter = parts.traceEmitter;
    this.tracer = parts.tracer;
    this.metricSignal = parts.metricSignal;
    this.traceSignal = parts.traceSignal;
    this.globalRegistered = parts.traceSignal.registration.tracer;
  }

  async flush(): Promise<void> {
    this.throwIfFailed('flush', await this.flushAll());
  }

  async shutdown(): Promise<void> {
    const flushed = await this.flushAll();
    const stopped = await this.settle('shutdown', [
      ['metrics', () => this.metricSignal.provider?.shutdown()],
      ['traces', () => this.traceSignal.provider?.shutdown()],
    ]);
    this.traceSignal.registration.release();
    this.throwIfFailed('shutdown', [...flushed, ...stopped]);
  }

  private flushAll(): Promise<TelemetryLifecycleError[]> {
    return this.settle('flush', [
      ['logs', () => this.settled(this.loggerSink.flush())],
      ['metrics', () => this.settled(this.metricsCollector.flush())],
      ['traces', () => this.settled(this.traceEmitter.flush())],
    ]);
  }

  private async settle(
    phase: LifecyclePhase,
    steps: readonly (readonly [TelemetrySignal, () => Promise<unknown> | undefined])[],
  ): Promise<TelemetryLifecycleError[]> {
    const results = await Promise.allSettled(
      steps.map(([signal, step]) =>
        Promise.resolve()
          .then(step)
          .catch((cause: unknown) => {
            throw new TelemetryLifecycleError(signal, phase, cause);
          }),
      ),
    );
    return results.flatMap(result => (result.status === 'rejected' ? [result.reason as TelemetryLifecycleError] : []));
  }

  private async settled(result: Result<void, Error>): Promise<void> {
    if (await result.isErr()) throw await result.unwrapErr();
  }

  private throwIfFailed(phase: LifecyclePhase, failures: readonly TelemetryLifecycleError[]): void {
    if (failures.length > 0) throw new AggregateError(failures, `OpenTelemetry ${phase} failed`);
  }
}

class OtelBootstrap {
  private readonly planner: OtelPlanner;
  private readonly logs: LoggerSignalFactory;
  private readonly metrics: MetricSignalFactory;
  private readonly traces: TraceSignalFactory;

  constructor(collaborators: OtelBootstrapCollaborators = {}) {
    this.planner = collaborators.planner ?? new OtelPlanner();
    this.logs = collaborators.logs ?? new LoggerSignalFactory();
    this.metrics = collaborators.metrics ?? new MetricSignalFactory();
    this.traces = collaborators.traces ?? new TraceSignalFactory();
  }

  init(block: OtelBlock, identity: AppIdentity, options: OtelInitOptions = {}): OtelRuntime {
    const plan = this.planner.plan(block, identity, options.environment ?? process.env);
    const scope = Object.freeze({ name: plan.identity.service, version: plan.identity.version });
    const seams = {
      logger: plan.live.logs ? options.seams?.logger : undefined,
      metrics: plan.live.metrics ? options.seams?.metrics : undefined,
      traces: plan.live.traces ? options.seams?.traces : undefined,
    };
    const loggerSignal = this.logs.create(
      seams.logger === undefined && plan.selections.logs.console,
      plan.resourceAttributes,
      options.destination,
    );
    const metricSignal =
      seams.metrics === undefined
        ? this.metrics.create({
            selection: plan.selections.metrics,
            resource: plan.resource,
            scope,
            settings: plan.metrics,
          })
        : this.metrics.inactive();
    const traceSignal =
      seams.traces === undefined
        ? this.traces.create({
            selection: plan.selections.traces,
            resource: plan.resource,
            scope,
            settings: plan.traces,
          })
        : this.traces.inactive(scope);
    return new OtelSession({
      active: Object.freeze({ logs: loggerSignal.active, metrics: metricSignal.active, traces: traceSignal.active }),
      block: plan.block,
      identity: plan.identity,
      logger: loggerSignal.logger,
      loggerSink: seams.logger ?? loggerSignal.sink,
      meter: metricSignal.meter,
      metricSignal,
      metricsCollector: seams.metrics ?? metricSignal.collector,
      otlpLogsBridge: loggerSignal.otlpBridge,
      resource: plan.resource,
      resourceAttributes: plan.resourceAttributes,
      traceEmitter: seams.traces ?? traceSignal.emitter,
      traceSignal,
      tracer: traceSignal.tracer,
    });
  }
}

export type {
  LifecyclePhase,
  OtelBootstrapCollaborators,
  OtelInitOptions,
  OtelRuntime,
  OtelSeamOverrides,
  TelemetrySignal,
};
export { OtelBootstrap, TelemetryLifecycleError };
