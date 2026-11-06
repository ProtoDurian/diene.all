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

  create(config: OtelSampler, environment: OtelEnvironment): Sampler | undefined {
    if (environment.has('OTEL_TRACES_SAMPLER')) return undefined;
    switch (config.type) {
      case 'always_on':
        return new AlwaysOnSampler();
      case 'always_off':
        return new AlwaysOffSampler();
      case 'parentbased_traceidratio':
        return new ParentBasedSampler({ root: new TraceIdRatioBasedSampler(config.ratio) });
    }
  }
}

export { TraceSamplerFactory };
