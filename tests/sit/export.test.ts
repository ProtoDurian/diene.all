import { afterAll, beforeAll, describe, it } from 'bun:test';
import { trace } from '@opentelemetry/api';
import 'should';
import { OtelBootstrap, type OtelRuntime } from '../../src/adapters/init';
import type { OtelBlock } from '../../src/lib/schema';
import { AppIdentityBuilder, OtelBlockFixtures } from '../../src/test-helper';
import { OtlpPayload } from './support/protobuf';
import { LoopbackOtlpReceiver } from './support/receiver';

const identity = new AppIdentityBuilder().with({ landscape: 'sit', service: 'otel-sit' }).build();
const receiver = new LoopbackOtlpReceiver();
const otlpOnly = new OtelBlockFixtures('http://127.0.0.1:4318').otlp();
const block: OtelBlock = { ...otlpOnly, logs: { ...otlpOnly.logs, enabled: false } };
let runtime: OtelRuntime;

beforeAll(async () => {
  // The schema pins the block to port 4318; the standard variable sends the real exporters to the ephemeral receiver.
  process.env.OTEL_EXPORTER_OTLP_ENDPOINT = receiver.origin;
  runtime = new OtelBootstrap().init(block, identity);
  await runtime.metricsCollector
    .record({ kind: 'counter', name: 'sit.jobs', value: 3, attributes: { queue: 'a' } })
    .unwrap();
  await runtime.traceEmitter.emit({ name: 'sit.work', attributes: { step: 1 } }).unwrap();
  await runtime.shutdown();
});

afterAll(async () => {
  delete process.env.OTEL_EXPORTER_OTLP_ENDPOINT;
  trace.disable();
  await receiver.stop();
});

describe.each([
  ['traces', '/v1/traces', OtlpPayload.spanNames, 'sit.work'],
  ['metrics', '/v1/metrics', OtlpPayload.metricNames, 'sit.jobs'],
] as const)('real OTLP http/protobuf export of %s', (_signal, path, names, expected) => {
  it('should post a protobuf body to the signal path', () => {
    // Arrange
    const exports = receiver.on(path);

    // Act
    const contentTypes = exports.map(entry => entry.contentType);

    // Assert
    exports.length.should.be.above(0);
    contentTypes.should.containEql('application/x-protobuf');
  });

  it('should carry the semconv and atomi.* resource attributes', () => {
    // Arrange
    const request = receiver.on(path)[0]?.body ?? new Map();

    // Act
    const attributes = OtlpPayload.resourceAttributes(request);

    // Assert
    attributes.should.match({
      'service.name': 'otel-sit',
      'deployment.environment.name': 'sit',
      'service.namespace': identity.platform,
      'service.version': identity.version,
      'atomi.landscape': 'sit',
      'atomi.module': identity.module,
    });
  });

  it('should deliver the emitted signal', () => {
    // Arrange
    const requests = receiver.on(path).map(entry => entry.body);

    // Act
    const delivered = requests.flatMap(request => names(request));

    // Assert
    delivered.should.containEql(expected);
  });
});
