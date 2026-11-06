import type { OtelBlock, OtelExporter } from './schema.js';

type OtelEnvironmentRecord = Readonly<Record<string, string | undefined>>;
type ExporterSelection = Readonly<{ console: boolean; otlp: boolean }>;
type ExporterVariable = 'OTEL_LOGS_EXPORTER' | 'OTEL_METRICS_EXPORTER' | 'OTEL_TRACES_EXPORTER';
type SignalFlags = Readonly<{ logs: boolean; metrics: boolean; traces: boolean }>;
type SignalSelections = Readonly<{ logs: ExporterSelection; metrics: ExporterSelection; traces: ExporterSelection }>;

const NO_EXPORTERS: ExporterSelection = Object.freeze({ console: false, otlp: false });

class OtelEnvironment {
  constructor(private readonly values: OtelEnvironmentRecord) {}

  value(name: string): string | undefined {
    const value = this.values[name]?.trim();
    return value === undefined || value === '' ? undefined : value;
  }

  has(name: string): boolean {
    return this.value(name) !== undefined;
  }

  positiveInteger(name: string): number | undefined {
    const value = this.value(name);
    return value !== undefined && /^\d+$/.test(value) && Number(value) > 0 ? Number(value) : undefined;
  }

  count(name: string): number | undefined {
    const value = this.value(name);
    return value !== undefined && /^\d+$/.test(value) ? Number(value) : undefined;
  }

  pairs(name: string): Readonly<Record<string, string>> | undefined {
    const value = this.value(name);
    if (value === undefined) return undefined;
    const entries = value.split(',').flatMap(entry => {
      const separator = entry.indexOf('=');
      const key = entry.slice(0, separator).trim();
      return separator <= 0 || key === '' ? [] : [[key, this.decode(entry.slice(separator + 1).trim())] as const];
    });
    return Object.freeze(Object.fromEntries(entries));
  }

  sdkDisabled(): boolean {
    return this.value('OTEL_SDK_DISABLED')?.toLowerCase() === 'true';
  }

  private decode(value: string): string {
    try {
      return decodeURIComponent(value);
    } catch {
      return value;
    }
  }
}

class ExporterSelector {
  // biome-ignore lint/complexity/noUselessConstructor: Bun coverage counts an implicit constructor as an uncovered function
  constructor() {}

  live(block: OtelBlock, environment: OtelEnvironment): SignalFlags {
    const disabled = environment.sdkDisabled();
    return Object.freeze({
      logs: !disabled && block.logs.enabled,
      metrics: !disabled && block.metrics.enabled,
      traces: !disabled && block.traces.enabled,
    });
  }

  select(configured: OtelExporter, variable: ExporterVariable, environment: OtelEnvironment): ExporterSelection {
    const override = environment.value(variable);
    if (override === undefined) {
      return Object.freeze({ console: configured.console.enabled, otlp: configured.otlp.enabled });
    }
    const names = new Set(override.split(',').map(name => name.trim().toLowerCase()));
    if (names.has('none')) return NO_EXPORTERS;
    return Object.freeze({ console: names.has('console'), otlp: names.has('otlp') });
  }

  selectAll(block: OtelBlock, environment: OtelEnvironment): SignalSelections {
    const live = this.live(block, environment);
    return Object.freeze({
      logs: live.logs ? this.select(block.logs.exporter, 'OTEL_LOGS_EXPORTER', environment) : NO_EXPORTERS,
      metrics: live.metrics ? this.select(block.metrics.exporter, 'OTEL_METRICS_EXPORTER', environment) : NO_EXPORTERS,
      traces: live.traces ? this.select(block.traces.exporter, 'OTEL_TRACES_EXPORTER', environment) : NO_EXPORTERS,
    });
  }
}

export type { ExporterSelection, ExporterVariable, OtelEnvironmentRecord, SignalFlags, SignalSelections };
export { ExporterSelector, OtelEnvironment };
