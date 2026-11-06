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

  it('should map the block into explicit options when no variable is set', () => {
    // Arrange
    const environment = new OtelEnvironment({});

    // Act
    const actual = factory.create(config, 'traces', environment);

    // Assert
    actual.should.eql({
      url: 'http://collector:4318/v1/traces',
      headers: { authorization: 'token' },
      timeoutMillis: 5000,
      compression: 'none',
      tls: {},
    });
  });

  it('should fall back to the local collector for an empty endpoint', () => {
    // Arrange
    const environment = new OtelEnvironment({});

    // Act
    const actual = factory.create({ ...config, endpoint: '' }, 'metrics', environment);

    // Assert
    actual.url.should.eql('http://localhost:4318/v1/metrics');
  });

  it('should resolve the generic variables into explicit options', () => {
    // Arrange
    const environment = new OtelEnvironment({
      OTEL_EXPORTER_OTLP_ENDPOINT: 'http://generic:4318/base',
      OTEL_EXPORTER_OTLP_HEADERS: 'tenant=a%20b,team=core',
      OTEL_EXPORTER_OTLP_TIMEOUT: '1500',
      OTEL_EXPORTER_OTLP_COMPRESSION: 'GZIP',
    });

    // Act
    const actual = factory.create(config, 'metrics', environment);

    // Assert
    actual.should.eql({
      url: 'http://generic:4318/base/v1/metrics',
      headers: { tenant: 'a b', team: 'core' },
      timeoutMillis: 1500,
      compression: 'gzip',
      tls: {},
    });
  });

  it('should let the signal variables win over the generic ones and use the signal endpoint as-is', () => {
    // Arrange
    const environment = new OtelEnvironment({
      OTEL_EXPORTER_OTLP_ENDPOINT: 'http://generic:4318',
      OTEL_EXPORTER_OTLP_TRACES_ENDPOINT: 'http://127.0.0.1:54321/custom',
      OTEL_EXPORTER_OTLP_HEADERS: 'tenant=generic,team=core',
      OTEL_EXPORTER_OTLP_TRACES_HEADERS: 'tenant=review',
      OTEL_EXPORTER_OTLP_TIMEOUT: '1500',
      OTEL_EXPORTER_OTLP_TRACES_TIMEOUT: '1234',
      OTEL_EXPORTER_OTLP_COMPRESSION: 'gzip',
      OTEL_EXPORTER_OTLP_TRACES_COMPRESSION: 'none',
    });

    // Act
    const actual = factory.create(config, 'traces', environment);

    // Assert
    actual.should.eql({
      url: 'http://127.0.0.1:54321/custom',
      headers: { tenant: 'review', team: 'core' },
      timeoutMillis: 1234,
      compression: 'none',
      tls: {},
    });
  });

  it('should name the generic certificate files for the exporter', () => {
    // Arrange
    const environment = new OtelEnvironment({
      OTEL_EXPORTER_OTLP_CERTIFICATE: '/certs/ca.pem',
      OTEL_EXPORTER_OTLP_CLIENT_CERTIFICATE: '/certs/client.pem',
      OTEL_EXPORTER_OTLP_CLIENT_KEY: '/certs/client.key',
    });

    // Act
    const actual = factory.create(config, 'metrics', environment);

    // Assert
    actual.tls.should.eql({
      ca: { path: '/certs/ca.pem', variable: 'OTEL_EXPORTER_OTLP_CERTIFICATE' },
      cert: { path: '/certs/client.pem', variable: 'OTEL_EXPORTER_OTLP_CLIENT_CERTIFICATE' },
      key: { path: '/certs/client.key', variable: 'OTEL_EXPORTER_OTLP_CLIENT_KEY' },
    });
  });

  it('should let a signal certificate variable win and leave unnamed files out', () => {
    // Arrange
    const environment = new OtelEnvironment({
      OTEL_EXPORTER_OTLP_CERTIFICATE: '/certs/generic-ca.pem',
      OTEL_EXPORTER_OTLP_TRACES_CERTIFICATE: '/certs/traces-ca.pem',
      OTEL_EXPORTER_OTLP_TRACES_CLIENT_KEY: '/certs/traces.key',
      OTEL_EXPORTER_OTLP_CLIENT_CERTIFICATE: ' ',
    });

    // Act
    const actual = factory.create(config, 'traces', environment);

    // Assert
    actual.tls.should.eql({
      ca: { path: '/certs/traces-ca.pem', variable: 'OTEL_EXPORTER_OTLP_TRACES_CERTIFICATE' },
      key: { path: '/certs/traces.key', variable: 'OTEL_EXPORTER_OTLP_TRACES_CLIENT_KEY' },
    });
  });

  it('should ignore a timeout that is not a positive integer', () => {
    // Arrange
    const environment = new OtelEnvironment({ OTEL_EXPORTER_OTLP_TIMEOUT: '0' });

    // Act
    const actual = factory.create(config, 'traces', environment);

    // Assert
    actual.timeoutMillis.should.eql(5000);
  });
});
