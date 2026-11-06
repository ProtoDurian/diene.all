import { describe, it } from 'bun:test';
import 'should';
import { WireDurationConverter } from '../../src/lib/duration';
import { OtlpEndpointPolicy, OtlpExporterOptionsFactory } from '../../src/lib/endpoint';
import { OtelEnvironment } from '../../src/lib/environment';
import type { OtelOtlpExporter } from '../../src/lib/schema';

const config: OtelOtlpExporter = {
  enabled: true,
  endpoint: 'http://collector:4318',
  protocol: 'http/protobuf',
  headers: { authorization: 'token' },
  timeout: 'PT5S',
};

describe('OtlpEndpointPolicy.accepts', () => {
  it.each([
    ['http on 4318', 'http://otel-collector:4318', true],
    ['https on 4318', 'https://otel-collector:4318', true],
    ['http on the wrong port', 'http://otel-collector:4317', false],
    ['no explicit port', 'http://otel-collector', false],
    ['a non-http scheme', 'ftp://otel-collector:4318', false],
    ['a non-URL string', 'not a url', false],
    ['an empty string', '', false],
  ])('should classify %s', (_label, input, expected) => {
    // Arrange
    const policy = new OtlpEndpointPolicy();

    // Act
    const actual = policy.accepts(input);

    // Assert
    actual.should.eql(expected);
  });
});

describe('OtlpEndpointPolicy.signalUrl', () => {
  it.each([
    ['a bare origin', 'http://c:4318', 'traces', 'http://c:4318/v1/traces'],
    ['a trailing slash', 'http://c:4318/', 'metrics', 'http://c:4318/v1/metrics'],
    ['a base path', 'http://c:4318/otel', 'traces', 'http://c:4318/otel/v1/traces'],
    ['the signal path already present', 'http://c:4318/v1/metrics', 'metrics', 'http://c:4318/v1/metrics'],
  ] as const)('should append the signal path to %s', (_label, endpoint, signal, expected) => {
    // Arrange
    const policy = new OtlpEndpointPolicy();

    // Act
    const actual = policy.signalUrl(endpoint, signal);

    // Assert
    actual.should.eql(expected);
  });
});

describe('OtlpExporterOptionsFactory', () => {
  const factory = new OtlpExporterOptionsFactory(new WireDurationConverter(), new OtlpEndpointPolicy());

  it('should map the block into url, headers and timeout when no variable is set', () => {
    // Arrange
    const environment = new OtelEnvironment({});

    // Act
    const actual = factory.create(config, 'traces', environment);

    // Assert
    actual.should.eql({
      url: 'http://collector:4318/v1/traces',
      headers: { authorization: 'token' },
      timeoutMillis: 5000,
    });
  });

  it('should omit the url for an empty endpoint', () => {
    // Arrange
    const environment = new OtelEnvironment({});

    // Act
    const actual = factory.create({ ...config, endpoint: '' }, 'metrics', environment);

    // Assert
    Object.keys(actual).should.eql(['headers', 'timeoutMillis']);
  });

  it.each([
    ['signal-specific', 'OTEL_EXPORTER_OTLP_METRICS_'],
    ['generic', 'OTEL_EXPORTER_OTLP_'],
  ])('should leave every setting to the SDK when the %s variables are set', (_label, prefix) => {
    // Arrange
    const environment = new OtelEnvironment({
      [`${prefix}ENDPOINT`]: 'http://other:4318',
      [`${prefix}HEADERS`]: 'a=b',
      [`${prefix}TIMEOUT`]: '1000',
    });

    // Act
    const actual = factory.create(config, 'metrics', environment);

    // Assert
    actual.should.eql({});
  });
});
