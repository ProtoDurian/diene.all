import { describe, it } from 'bun:test';
import { ParentBasedSampler } from '@opentelemetry/sdk-trace-base';
import { ATTR_SERVICE_NAME } from '@opentelemetry/semantic-conventions';
import should from 'should';
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
      otlp: { url: 'http://collector:4318/v1/metrics', headers: {}, timeoutMillis: 10_000 },
    });
    actual.traces.otlp.should.eql({ url: 'http://collector:4318/v1/traces', headers: {}, timeoutMillis: 10_000 });
    (actual.traces.sampler instanceof ParentBasedSampler).should.be.true();
    actual.resourceAttributes[ATTR_SERVICE_NAME]?.should.eql('svc');
    actual.resource.attributes.should.eql(actual.resourceAttributes);
  });

  it.each([
    ['positive integers', '5', '7', 5, 7],
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

  it('should leave the sampler to the SDK when OTEL_TRACES_SAMPLER is set', () => {
    // Arrange
    const environment = { OTEL_TRACES_SAMPLER: 'always_off' };

    // Act
    const actual = planner.plan(block, identity, environment);

    // Assert
    should(actual.traces.sampler).be.undefined();
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
