import type { WireDurationConverter } from './duration.js';
import type { OtelEnvironment } from './environment.js';
import type { OtelOtlpExporter } from './schema.js';

type OtlpSignal = 'metrics' | 'traces';
type OtlpCompression = 'gzip' | 'none';

interface OtlpExporterOptions {
  readonly compression: OtlpCompression;
  readonly headers: Readonly<Record<string, string>>;
  readonly timeoutMillis: number;
  readonly url: string;
}

class OtlpEndpointPolicy {
  constructor(private readonly port = '4318') {}

  accepts(value: string): boolean {
    try {
      const endpoint = new URL(value);
      return (endpoint.protocol === 'http:' || endpoint.protocol === 'https:') && endpoint.port === this.port;
    } catch {
      return false;
    }
  }

  signalUrl(endpoint: string, signal: OtlpSignal): string {
    const url = new URL(endpoint);
    const signalPath = `/v1/${signal}`;
    const basePath = url.pathname.replace(/\/$/, '');
    url.pathname = basePath.endsWith(signalPath) ? basePath : `${basePath}${signalPath}`;
    return url.toString();
  }
}

class OtlpExporterOptionsFactory {
  constructor(
    private readonly durations: WireDurationConverter,
    private readonly endpoints: OtlpEndpointPolicy,
    private readonly fallbackEndpoint = 'http://localhost:4318',
  ) {}

  create(config: OtelOtlpExporter, signal: OtlpSignal, environment: OtelEnvironment): OtlpExporterOptions {
    const specific = (setting: string) => `OTEL_EXPORTER_OTLP_${signal.toUpperCase()}_${setting}`;
    const generic = (setting: string) => `OTEL_EXPORTER_OTLP_${setting}`;
    const signalEndpoint = environment.value(specific('ENDPOINT'));
    const genericEndpoint = environment.value(generic('ENDPOINT'));
    const genericHeaders = environment.pairs(generic('HEADERS'));
    const signalHeaders = environment.pairs(specific('HEADERS'));
    const compression = (
      environment.value(specific('COMPRESSION')) ?? environment.value(generic('COMPRESSION'))
    )?.toLowerCase();
    return Object.freeze({
      url:
        signalEndpoint ??
        this.endpoints.signalUrl(genericEndpoint ?? (config.endpoint || this.fallbackEndpoint), signal),
      headers:
        genericHeaders === undefined && signalHeaders === undefined
          ? Object.freeze({ ...config.headers })
          : Object.freeze({ ...genericHeaders, ...signalHeaders }),
      timeoutMillis:
        environment.positiveInteger(specific('TIMEOUT')) ??
        environment.positiveInteger(generic('TIMEOUT')) ??
        this.durations.toMilliseconds(config.timeout),
      compression: compression === 'gzip' ? 'gzip' : 'none',
    });
  }
}

export type { OtlpCompression, OtlpExporterOptions, OtlpSignal };
export { OtlpEndpointPolicy, OtlpExporterOptionsFactory };
