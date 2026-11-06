import {
  AlwaysOffSampler,
  AlwaysOnSampler,
  ParentBasedSampler,
  type Sampler,
  TraceIdRatioBasedSampler,
} from '@opentelemetry/sdk-trace-base';
import type { OtelEnvironment } from './environment.js';
import type { OtelSampler } from './schema.js';

class TraceSamplerFactory {
  // biome-ignore lint/complexity/noUselessConstructor: Bun coverage counts an implicit constructor as an uncovered function
  constructor() {}

  create(config: OtelSampler, environment: OtelEnvironment): Sampler {
    const ratio = this.ratio(environment);
    switch (environment.value('OTEL_TRACES_SAMPLER')?.toLowerCase()) {
      case 'always_on':
        return new AlwaysOnSampler();
      case 'always_off':
        return new AlwaysOffSampler();
      case 'traceidratio':
        return new TraceIdRatioBasedSampler(ratio);
      case 'parentbased_always_on':
        return new ParentBasedSampler({ root: new AlwaysOnSampler() });
      case 'parentbased_always_off':
        return new ParentBasedSampler({ root: new AlwaysOffSampler() });
      case 'parentbased_traceidratio':
        return new ParentBasedSampler({ root: new TraceIdRatioBasedSampler(ratio) });
      default:
        return this.fromBlock(config);
    }
  }

  private fromBlock(config: OtelSampler): Sampler {
    switch (config.type) {
      case 'always_on':
        return new AlwaysOnSampler();
      case 'always_off':
        return new AlwaysOffSampler();
      case 'parentbased_traceidratio':
        return new ParentBasedSampler({ root: new TraceIdRatioBasedSampler(config.ratio) });
    }
  }

  private ratio(environment: OtelEnvironment): number {
    const ratio = Number(environment.value('OTEL_TRACES_SAMPLER_ARG') ?? 'none');
    return Number.isFinite(ratio) && ratio >= 0 && ratio <= 1 ? ratio : 1;
  }
}

export { TraceSamplerFactory };
