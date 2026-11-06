import { describe, it } from 'bun:test';
import { context, ROOT_CONTEXT, SpanKind, trace } from '@opentelemetry/api';
import { AlwaysOffSampler, AlwaysOnSampler, ParentBasedSampler, SamplingDecision } from '@opentelemetry/sdk-trace-base';
import should from 'should';
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
    const actual = sampler?.shouldSample(ROOT_CONTEXT, 'ab'.repeat(16), 'root', SpanKind.INTERNAL, {}, []);

    // Assert
    (actual?.decision ?? 'none').should.eql(expected);
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
    const actual = sampler?.shouldSample(parent, 'ab'.repeat(16), 'child', SpanKind.INTERNAL, {}, []);

    // Assert
    (actual?.decision ?? 'none').should.eql(SamplingDecision.RECORD_AND_SAMPLED);
  });

  it('should leave the sampler to the SDK when OTEL_TRACES_SAMPLER is set', () => {
    // Arrange
    const environment = new OtelEnvironment({ OTEL_TRACES_SAMPLER: 'traceidratio' });

    // Act
    const actual = factory.create({ type: 'always_on', ratio: 1 }, environment);

    // Assert
    should(actual).be.undefined();
  });
});
