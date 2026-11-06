import { describe, it } from 'bun:test';
import { context, ROOT_CONTEXT, SpanKind, trace } from '@opentelemetry/api';
import {
  AlwaysOffSampler,
  AlwaysOnSampler,
  ParentBasedSampler,
  SamplingDecision,
  TraceIdRatioBasedSampler,
} from '@opentelemetry/sdk-trace-base';
import 'should';
import { OtelEnvironment } from '../../src/lib/environment';
import { TraceSamplerFactory } from '../../src/lib/sampler';
import type { OtelSampler } from '../../src/lib/schema';

const factory = new TraceSamplerFactory();
const none = new OtelEnvironment({});

describe('TraceSamplerFactory', () => {
  it.each([
    ['always_on', AlwaysOnSampler],
    ['always_off', AlwaysOffSampler],
    ['parentbased_traceidratio', ParentBasedSampler],
  ] as const)('should map %s to its native sampler', (type, expected) => {
    // Arrange
    const config: OtelSampler = { type, ratio: 1 };

    // Act
    const actual = factory.create(config, none);

    // Assert
    (actual instanceof expected).should.be.true();
  });

  it.each([
    [0, SamplingDecision.NOT_RECORD],
    [1, SamplingDecision.RECORD_AND_SAMPLED],
  ])('should sample a root span by the ratio %d', (ratio, expected) => {
    // Arrange
    const sampler = factory.create({ type: 'parentbased_traceidratio', ratio }, none);

    // Act
    const actual = sampler.shouldSample(ROOT_CONTEXT, 'ab'.repeat(16), 'root', SpanKind.INTERNAL, {}, []);

    // Assert
    actual.decision.should.eql(expected);
  });

  it('should follow a sampled parent even at ratio 0', () => {
    // Arrange
    const sampler = factory.create({ type: 'parentbased_traceidratio', ratio: 0 }, none);
    const parent = trace.setSpanContext(context.active(), {
      traceId: 'ab'.repeat(16),
      spanId: 'cd'.repeat(8),
      traceFlags: 1,
      isRemote: true,
    });

    // Act
    const actual = sampler.shouldSample(parent, 'ab'.repeat(16), 'child', SpanKind.INTERNAL, {}, []);

    // Assert
    actual.decision.should.eql(SamplingDecision.RECORD_AND_SAMPLED);
  });

  it.each([
    ['always_on', AlwaysOnSampler, 'AlwaysOnSampler'],
    ['ALWAYS_OFF', AlwaysOffSampler, 'AlwaysOffSampler'],
    ['traceidratio', TraceIdRatioBasedSampler, 'TraceIdRatioBased{0.5}'],
    ['parentbased_always_on', ParentBasedSampler, 'ParentBased{root=AlwaysOnSampler'],
    ['parentbased_always_off', ParentBasedSampler, 'ParentBased{root=AlwaysOffSampler'],
    ['parentbased_traceidratio', ParentBasedSampler, 'ParentBased{root=TraceIdRatioBased{0.5}'],
  ] as const)('should build %s from OTEL_TRACES_SAMPLER over the block', (name, type, description) => {
    // Arrange
    const environment = new OtelEnvironment({ OTEL_TRACES_SAMPLER: name, OTEL_TRACES_SAMPLER_ARG: '0.5' });

    // Act
    const actual = factory.create({ type: 'always_off', ratio: 0 }, environment);

    // Assert
    (actual instanceof type).should.be.true();
    actual.toString().should.startWith(description);
  });

  it.each([
    ['missing', undefined],
    ['out of range', '2'],
    ['not a number', 'half'],
  ])('should default a %s sampler argument to 1', (_label, arg) => {
    // Arrange
    const environment = new OtelEnvironment({ OTEL_TRACES_SAMPLER: 'traceidratio', OTEL_TRACES_SAMPLER_ARG: arg });

    // Act
    const actual = factory.create({ type: 'always_off', ratio: 0 }, environment);

    // Assert
    actual.toString().should.eql('TraceIdRatioBased{1}');
  });

  it('should keep the block sampler for an unknown OTEL_TRACES_SAMPLER', () => {
    // Arrange
    const environment = new OtelEnvironment({ OTEL_TRACES_SAMPLER: 'jaeger_remote' });

    // Act
    const actual = factory.create({ type: 'always_off', ratio: 0 }, environment);

    // Assert
    (actual instanceof AlwaysOffSampler).should.be.true();
  });
});
