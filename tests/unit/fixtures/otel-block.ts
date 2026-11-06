type Json = Readonly<Record<string, unknown>>;

interface AcceptCase {
  readonly name: string;
  readonly block: Json;
}

interface RejectCase {
  readonly name: string;
  readonly violates: string;
  readonly block: Json;
}

const VALID_OTLP_ENDPOINT = 'http://otel-collector:4318';
const WRONG_PORT_ENDPOINT = 'http://otel-collector:4317';

function otlp(overrides: Json = {}): Json {
  return { enabled: false, endpoint: '', protocol: 'http/protobuf', headers: {}, timeout: 'PT10S', ...overrides };
}

function exporter(consoleEnabled = false, otlpOverrides: Json = {}): Json {
  return { console: { enabled: consoleEnabled }, otlp: otlp(otlpOverrides) };
}

function block(overrides: { logs?: Json; metrics?: Json; traces?: Json; sampler?: Json; exporter?: Json } = {}): Json {
  const shared = overrides.exporter ?? exporter();
  return {
    logs: { enabled: true, exporter: shared, ...overrides.logs },
    metrics: { enabled: true, exporter: shared, interval: 'PT60S', ...overrides.metrics },
    traces: {
      enabled: true,
      sampler: overrides.sampler ?? { type: 'parentbased_traceidratio', ratio: 1.0 },
      exporter: shared,
      ...overrides.traces,
    },
  };
}

const canonicalOtelBlock: Json = block();

const acceptCases: readonly AcceptCase[] = [
  { name: 'the canonical block (all signals on, all exporters off)', block: canonicalOtelBlock },
  {
    name: 'OTLP enabled on every signal with a port-4318 endpoint',
    block: block({ exporter: exporter(false, { enabled: true, endpoint: VALID_OTLP_ENDPOINT }) }),
  },
  { name: 'console exporters enabled on every signal', block: block({ exporter: exporter(true) }) },
  { name: 'always_on sampler', block: block({ sampler: { type: 'always_on', ratio: 1 } }) },
  { name: 'always_off sampler', block: block({ sampler: { type: 'always_off', ratio: 0 } }) },
  { name: 'sampler ratio at 0', block: block({ sampler: { type: 'parentbased_traceidratio', ratio: 0 } }) },
  { name: 'sampler ratio at 1', block: block({ sampler: { type: 'parentbased_traceidratio', ratio: 1 } }) },
  {
    name: 'an https endpoint with a path, custom headers and a non-default timeout and interval',
    block: block({
      exporter: exporter(false, {
        enabled: true,
        endpoint: 'https://otel-collector:4318/base',
        headers: { authorization: 'Bearer token' },
        timeout: 'PT2.5S',
      }),
      metrics: { interval: 'PT1M' },
    }),
  },
  {
    name: 'every signal disabled',
    block: block({ logs: { enabled: false }, metrics: { enabled: false }, traces: { enabled: false } }),
  },
];

const rejectCases: readonly RejectCase[] = [
  {
    name: 'signal key logging instead of logs',
    violates: 'signal keys are exactly logs, metrics and traces',
    block: { logging: canonicalOtelBlock.logs, metrics: canonicalOtelBlock.metrics, traces: canonicalOtelBlock.traces },
  },
  {
    name: 'signal key Logs instead of logs',
    violates: 'signal keys are case-sensitive',
    block: { Logs: canonicalOtelBlock.logs, metrics: canonicalOtelBlock.metrics, traces: canonicalOtelBlock.traces },
  },
  {
    name: 'exporter as an enum string',
    violates: 'exporters are independent enabled flags',
    block: block({ logs: { exporter: 'otlp' } }),
  },
  {
    name: 'exporter with an unknown key',
    violates: 'the exporter object is strict',
    block: block({ exporter: { ...exporter(), use: 'otlp' } }),
  },
  {
    name: 'sampler ratio below 0',
    violates: 'ratio is within [0, 1]',
    block: block({ sampler: { type: 'parentbased_traceidratio', ratio: -0.1 } }),
  },
  {
    name: 'sampler ratio above 1',
    violates: 'ratio is within [0, 1]',
    block: block({ sampler: { type: 'parentbased_traceidratio', ratio: 1.1 } }),
  },
  {
    name: 'sampler ratio NaN',
    violates: 'ratio is finite',
    block: block({ sampler: { type: 'parentbased_traceidratio', ratio: Number.NaN } }),
  },
  {
    name: 'unknown sampler type',
    violates: 'sampler type is one of three values',
    block: block({ sampler: { type: 'traceidratio', ratio: 1 } }),
  },
  {
    name: 'a non-ISO 8601 OTLP timeout',
    violates: 'durations are canonical ISO 8601 strings',
    block: block({ exporter: exporter(false, { timeout: '10s' }) }),
  },
  {
    name: 'a zero metrics interval',
    violates: 'durations are positive',
    block: block({ metrics: { interval: 'PT0S' } }),
  },
  {
    name: 'an enabled OTLP exporter with no endpoint',
    violates: 'an enabled OTLP exporter carries an endpoint',
    block: block({ exporter: exporter(false, { enabled: true }) }),
  },
  {
    name: 'an OTLP endpoint on port 4317',
    violates: 'OTLP is http/protobuf on port 4318',
    block: block({ exporter: exporter(false, { enabled: true, endpoint: WRONG_PORT_ENDPOINT }) }),
  },
  {
    name: 'a disabled OTLP exporter with a wrong-port endpoint',
    violates: 'a present endpoint is checked even when disabled',
    block: block({ exporter: exporter(false, { endpoint: WRONG_PORT_ENDPOINT }) }),
  },
  {
    name: 'the grpc protocol',
    violates: 'the protocol is the http/protobuf literal',
    block: block({ exporter: exporter(false, { protocol: 'grpc' }) }),
  },
  {
    name: 'no traces signal',
    violates: 'all three signals are required',
    block: { logs: canonicalOtelBlock.logs, metrics: canonicalOtelBlock.metrics },
  },
];

export { acceptCases, canonicalOtelBlock, rejectCases };
