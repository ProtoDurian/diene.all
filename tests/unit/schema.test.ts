import { describe, it } from 'bun:test';
import 'should';
import { WireDurationConverter } from '../../src/lib/duration';
import { OtlpEndpointPolicy } from '../../src/lib/endpoint';
import {
  defaultOtelBlock,
  OtelSchemaFactory,
  otelBlockSchema,
  otelOtlpExporterSchema,
  otelSamplerSchema,
  wireDurationSchema,
} from '../../src/lib/schema';
import { acceptCases, canonicalOtelBlock, rejectCases } from './fixtures/otel-block';

describe('otelBlockSchema', () => {
  it.each([...acceptCases])('should accept $name', ({ block }) => {
    // Arrange
    const input = block;

    // Act
    const actual = otelBlockSchema.safeParse(input);

    // Assert
    actual.success.should.be.true();
  });

  it.each([...rejectCases])('should reject $name ($violates)', ({ block }) => {
    // Arrange
    const input = block;

    // Act
    const actual = otelBlockSchema.safeParse(input);

    // Assert
    actual.success.should.be.false();
  });

  it('should keep the canonical defaults when parsing the canonical block', () => {
    // Arrange
    const input = canonicalOtelBlock;

    // Act
    const parsed = otelBlockSchema.parse(input);

    // Assert
    parsed.metrics.interval.should.eql('PT60S');
    parsed.traces.sampler.should.eql({ type: 'parentbased_traceidratio', ratio: 1 });
    parsed.traces.exporter.otlp.protocol.should.eql('http/protobuf');
  });

  it('should accept defaultOtelBlock and match the canonical block', () => {
    // Arrange
    const input = defaultOtelBlock;

    // Act
    const actual = otelBlockSchema.parse(input);

    // Assert
    actual.should.eql(otelBlockSchema.parse(canonicalOtelBlock));
  });
});

describe('wireDurationSchema', () => {
  it.each([
    ['PT30S', true],
    ['30 seconds', false],
    ['P1M', false],
  ])('should classify %s as %s', (input, expected) => {
    // Arrange
    const value = input;

    // Act
    const actual = wireDurationSchema.safeParse(value);

    // Assert
    actual.success.should.eql(expected);
  });

  it('should report the converter message on a bad duration', () => {
    // Arrange
    const value = 'PT0S';

    // Act
    const actual = wireDurationSchema.safeParse(value);

    // Assert
    actual.error?.issues[0]?.message.should.eql(
      'Duration must be a positive, fixed-length canonical ISO 8601 duration',
    );
  });

  it('should fall back to the fixed message when the converter throws a non-Error', () => {
    // Arrange
    const converter = new WireDurationConverter(() => {
      throw 'boom';
    });
    const schema = new OtelSchemaFactory(converter, new OtlpEndpointPolicy()).duration();

    // Act
    const actual = schema.safeParse('PT1S');

    // Assert
    actual.error?.issues[0]?.message.should.eql(
      'Duration must be a positive, fixed-length canonical ISO 8601 duration',
    );
  });
});

describe('otelSamplerSchema', () => {
  it('should reject an out-of-range ratio', () => {
    // Arrange
    const sampler = { type: 'always_on', ratio: 2 };

    // Act
    const actual = otelSamplerSchema.safeParse(sampler);

    // Assert
    actual.success.should.be.false();
  });
});

describe('otelOtlpExporterSchema', () => {
  it('should name the endpoint path on an enabled exporter without an endpoint', () => {
    // Arrange
    const exporter = { enabled: true, endpoint: '', protocol: 'http/protobuf', headers: {}, timeout: 'PT10S' };

    // Act
    const actual = otelOtlpExporterSchema.safeParse(exporter);

    // Assert
    actual.error?.issues.map(issue => issue.path.join('.')).should.eql(['endpoint']);
  });

  it('should enforce the injected endpoint port', () => {
    // Arrange
    const schema = new OtelSchemaFactory(new WireDurationConverter(), new OtlpEndpointPolicy('9999')).otlpExporter();
    const exporter = {
      enabled: true,
      endpoint: 'http://c:4318',
      protocol: 'http/protobuf',
      headers: {},
      timeout: 'PT10S',
    };

    // Act
    const actual = schema.safeParse(exporter);

    // Assert
    actual.success.should.be.false();
  });
});
