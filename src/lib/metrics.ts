import type { Result } from '@atomicloud/diene.result';
import { type MetricsError, PortError } from './error.js';
import { type TelemetryAttributes, TelemetryPolicy } from './telemetry.js';
import { type Checked, PortPolicy } from './validation.js';

type MetricKind = 'counter' | 'gauge' | 'histogram';

interface MetricRecord {
  readonly kind: MetricKind;
  readonly name: string;
  readonly value: number;
  readonly unit?: string;
  readonly attributes?: TelemetryAttributes;
}

interface MetricsCollector {
  record(metric: MetricRecord): Result<void, MetricsError>;
  flush(): Result<void, MetricsError>;
}

const METRIC_NAME = /^[A-Za-z][A-Za-z0-9_.\-/]{0,254}$/;

class MetricsPolicy extends PortPolicy {
  constructor(private readonly telemetry: TelemetryPolicy = new TelemetryPolicy()) {
    super();
  }

  checkRecord(metric: MetricRecord): Checked<Readonly<MetricRecord>, MetricsError> {
    if (typeof metric !== 'object' || metric === null) {
      return this.invalid('metric', 'Metric record must be an object');
    }
    if (metric.kind !== 'counter' && metric.kind !== 'gauge' && metric.kind !== 'histogram') {
      return this.invalid('kind', 'Metric kind is invalid');
    }
    if (typeof metric.name !== 'string' || !METRIC_NAME.test(metric.name)) {
      return this.invalid('name', 'Metric name must be a valid portable instrument name');
    }
    if (typeof metric.value !== 'number' || !Number.isFinite(metric.value)) {
      return this.invalid('value', 'Metric value must be finite');
    }
    if ((metric.kind === 'counter' || metric.kind === 'histogram') && metric.value < 0) {
      return this.invalid('value', 'Counter and histogram values must not be negative');
    }
    if (metric.unit !== undefined && (typeof metric.unit !== 'string' || metric.unit.trim() === '')) {
      return this.invalid('unit', 'Metric unit must not be blank');
    }
    const attributes = this.telemetry.checkAttributes(metric.attributes, 'metrics', 'record');
    if (!attributes.ok) return attributes;
    return this.accept(
      Object.freeze({
        ...(attributes.value === undefined ? {} : { attributes: attributes.value }),
        kind: metric.kind,
        name: metric.name,
        value: metric.value,
        ...(metric.unit === undefined ? {} : { unit: metric.unit }),
      }),
    );
  }

  validateRecord(metric: MetricRecord): Result<Readonly<MetricRecord>, MetricsError> {
    return this.toResult(this.checkRecord(metric));
  }

  private invalid(field: string, message: string): Checked<never, MetricsError> {
    return this.reject(new PortError('metrics', 'invalid-input', 'record', message, { field }));
  }
}

export type { MetricKind, MetricRecord, MetricsCollector };
export { MetricsPolicy };
