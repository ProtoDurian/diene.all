import { describe, it } from 'bun:test';
import { AlwaysOffSampler, ParentBasedSampler } from '@opentelemetry/sdk-trace-base';
import { ATTR_SERVICE_NAME } from '@opentelemetry/semantic-conventions';
import 'should';
import { OtelPlanner } from '../../src/lib/plan';
import type { AppIdentity } from '../../src/lib/resource';
import { defaultOtelBlock, type OtelBlock } from '../../src/lib/schema';

const identity: AppIdentity = {
  landscape: 'lapras',
  platform: 'atomi',
  service: 'svc',
  module: 'api',
  version: '2.0.0',
};
const otlp = { ...defaultOtelBlock.logs.exporter.otlp, enabled: true, endpoint: 'http://collector:4318' };
const exporter = { console: { enabled: false }, otlp };
const block: OtelBlock = {
  logs: { enabled: true, exporter: { ...exporter, console: { enabled: true } } },
  metrics: { enabled: true, exporter, interval: 'PT30S' },
  traces: { ...defaultOtelBlock.traces, exporter },
};
const planner = new OtelPlanner();

describe('OtelPlanner', () => {
  it('should plan every signal from the block alone', () => {
    // Arrange
    const environment = {};

    // Act
    const actual = planner.plan(block, identity, environment);

    // Assert
    actual.live.should.eql({ logs: true, metrics: true, traces: true });
    actual.selections.should.eql({
      logs: { console: true, otlp: true },
      metrics: { console: false, otlp: true },
      traces: { console: false, otlp: true },
    });
    actual.metrics.should.eql({
      intervalMillis: 30_000,
      timeoutMillis: 10_000,
      temporality: 'cumulative',
      otlp: { url: 'http://collector:4318/v1/metrics', headers: {}, timeoutMillis: 10_000, compression: 'none' },
    });
    actual.traces.otlp.should.eql({
      url: 'http://collector:4318/v1/traces',
      headers: {},
      timeoutMillis: 10_000,
      compression: 'none',
    });
    actual.traces.batch.should.eql({
      exportTimeoutMillis: 30_000,
      maxExportBatchSize: 512,
      maxQueueSize: 2048,
      scheduledDelayMillis: 5000,
    });
    (actual.traces.sampler instanceof ParentBasedSampler).should.be.true();
    actual.resourceAttributes[ATTR_SERVICE_NAME]?.should.eql('svc');
    actual.resource.attributes.should.eql(actual.resourceAttributes);
  });

  it.each([
    ['positive integers', '20', '7', 20, 7],
    ['an interval below the timeout', '1000', undefined, 1000, 1000],
    ['zero', '0', '0', 30_000, 10_000],
    ['non-numeric text', 'soon', '1s', 30_000, 10_000],
  ])('should read metric export overrides given as %s', (_label, interval, timeout, wantInterval, wantTimeout) => {
    // Arrange
    const environment = { OTEL_METRIC_EXPORT_INTERVAL: interval, OTEL_METRIC_EXPORT_TIMEOUT: timeout };

    // Act
    const actual = planner.plan(block, identity, environment);

    // Assert
    actual.metrics.intervalMillis.should.eql(wantInterval);
    actual.metrics.timeoutMillis.should.eql(wantTimeout);
  });

  it('should clamp the reader timeout to a short block interval', () => {
    // Arrange
    const short: OtelBlock = { ...block, metrics: { ...block.metrics, interval: 'PT1S' } };

    // Act
    const actual = planner.plan(short, identity, {});

    // Assert
    actual.metrics.should.match({ intervalMillis: 1000, timeoutMillis: 1000 });
  });

  it('should read the batch processor and temporality variables', () => {
    // Arrange
    const environment = {
      OTEL_BSP_EXPORT_TIMEOUT: '1',
      OTEL_BSP_MAX_EXPORT_BATCH_SIZE: '2',
      OTEL_BSP_MAX_QUEUE_SIZE: '3',
      OTEL_BSP_SCHEDULE_DELAY: '4',
      OTEL_EXPORTER_OTLP_METRICS_TEMPORALITY_PREFERENCE: 'Delta',
    };

    // Act
    const actual = planner.plan(block, identity, environment);

    // Assert
    actual.traces.batch.should.eql({
      exportTimeoutMillis: 1,
      maxExportBatchSize: 2,
      maxQueueSize: 3,
      scheduledDelayMillis: 4,
    });
    actual.metrics.temporality.should.eql('delta');
  });

  it('should fall back to cumulative for an unknown temporality', () => {
    // Arrange
    const environment = { OTEL_EXPORTER_OTLP_METRICS_TEMPORALITY_PREFERENCE: 'sometimes' };

    // Act
    const actual = planner.plan(block, identity, environment);

    // Assert
    actual.metrics.temporality.should.eql('cumulative');
  });

  it('should take the sampler from OTEL_TRACES_SAMPLER', () => {
    // Arrange
    const environment = { OTEL_TRACES_SAMPLER: 'always_off' };

    // Act
    const actual = planner.plan(block, identity, environment);

    // Assert
    (actual.traces.sampler instanceof AlwaysOffSampler).should.be.true();
  });

  it.each([
    ['an invalid block', { ...block, logs: { enabled: 'yes' } } as unknown as OtelBlock, identity],
    ['an invalid identity', block, { ...identity, service: '' }],
  ])('should throw on %s', (_label, input, who) => {
    // Arrange
    const environment = {};

    // Act
    const act = () => planner.plan(input, who, environment);

    // Assert
    act.should.throw();
  });
});
