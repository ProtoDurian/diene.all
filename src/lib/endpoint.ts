import type { WireDurationConverter } from './duration.js';
import type { OtelEnvironment } from './environment.js';
import type { OtelOtlpExporter } from './schema.js';

type OtlpSignal = 'metrics' | 'traces';

interface OtlpExporterOptions {
  readonly headers?: Readonly<Record<string, string>>;
  readonly timeoutMillis?: number;
  readonly url?: string;
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
  ) {}

  create(config: OtelOtlpExporter, signal: OtlpSignal, environment: OtelEnvironment): OtlpExporterOptions {
    const fromEnvironment = (setting: string): boolean =>
      environment.has(`OTEL_EXPORTER_OTLP_${signal.toUpperCase()}_${setting}`) ||
      environment.has(`OTEL_EXPORTER_OTLP_${setting}`);
    return Object.freeze({
      ...(config.endpoint === '' || fromEnvironment('ENDPOINT')
        ? {}
        : { url: this.endpoints.signalUrl(config.endpoint, signal) }),
      ...(fromEnvironment('HEADERS') ? {} : { headers: Object.freeze({ ...config.headers }) }),
      ...(fromEnvironment('TIMEOUT') ? {} : { timeoutMillis: this.durations.toMilliseconds(config.timeout) }),
    });
  }
}

export type { OtlpExporterOptions, OtlpSignal };
export { OtlpEndpointPolicy, OtlpExporterOptionsFactory };
