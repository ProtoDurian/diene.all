import type { LoggerSink, MetricsCollector, TelemetryAttributes } from '@atomicloud/diene.interfaces';
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

interface OtelRuntime {
  readonly active: SignalFlags;
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

type OtelSessionParts = Omit<OtelRuntime, 'flush' | 'shutdown'> &
  Readonly<{ metricSignal: MetricSignal; traceSignal: TraceSignal }>;

class OtelSession implements OtelRuntime {
  readonly active: SignalFlags;
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
  }

  async flush(): Promise<void> {
    await Promise.all([
      this.loggerSink.flush().unwrap(),
      this.metricsCollector.flush().unwrap(),
      this.traceEmitter.flush().unwrap(),
    ]);
  }

  async shutdown(): Promise<void> {
    const flushed = await Promise.allSettled([this.flush()]);
    const stopped = await Promise.allSettled([
      this.metricSignal.provider?.shutdown(),
      this.traceSignal.provider?.shutdown(),
    ]);
    const failures = [...flushed, ...stopped].flatMap(result => (result.status === 'rejected' ? [result.reason] : []));
    if (failures.length > 0) throw new AggregateError(failures, 'OpenTelemetry shutdown failed');
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

export type { OtelBootstrapCollaborators, OtelInitOptions, OtelRuntime, OtelSeamOverrides };
export { OtelBootstrap };
