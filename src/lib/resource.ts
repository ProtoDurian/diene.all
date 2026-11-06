import type { TelemetryAttributes } from '@atomicloud/diene.interfaces';
import { type Resource, resourceFromAttributes } from '@opentelemetry/resources';
import {
  ATTR_DEPLOYMENT_ENVIRONMENT_NAME,
  ATTR_SERVICE_NAME,
  ATTR_SERVICE_NAMESPACE,
  ATTR_SERVICE_VERSION,
} from '@opentelemetry/semantic-conventions';
import { z } from 'zod';
import type { OtelEnvironment } from './environment.js';

const identityValueSchema = z.string().trim().min(1);

const appIdentitySchema = z
  .object({
    landscape: identityValueSchema,
    platform: identityValueSchema,
    service: identityValueSchema,
    module: identityValueSchema,
    version: identityValueSchema,
  })
  .strict()
  .readonly();

type AppIdentity = z.infer<typeof appIdentitySchema>;

class ResourceIdentityMapper {
  // biome-ignore lint/complexity/noUselessConstructor: Bun coverage counts an implicit constructor as an uncovered function
  constructor() {}

  semantic(identity: AppIdentity): TelemetryAttributes {
    const app = appIdentitySchema.parse(identity);
    return Object.freeze({
      [ATTR_DEPLOYMENT_ENVIRONMENT_NAME]: app.landscape,
      [ATTR_SERVICE_NAMESPACE]: app.platform,
      [ATTR_SERVICE_NAME]: app.service,
      [ATTR_SERVICE_VERSION]: app.version,
      'atomi.landscape': app.landscape,
      'atomi.module': app.module,
      'atomi.platform': app.platform,
      'atomi.service': app.service,
      'atomi.version': app.version,
    });
  }

  standard(environment: OtelEnvironment): TelemetryAttributes {
    return environment.pairs('OTEL_RESOURCE_ATTRIBUTES') ?? Object.freeze({});
  }

  attributes(identity: AppIdentity, environment: OtelEnvironment): TelemetryAttributes {
    const serviceName = environment.value('OTEL_SERVICE_NAME');
    return Object.freeze({
      ...this.semantic(identity),
      ...this.standard(environment),
      ...(serviceName === undefined ? {} : { [ATTR_SERVICE_NAME]: serviceName }),
    });
  }

  resource(identity: AppIdentity, environment: OtelEnvironment): Resource {
    return resourceFromAttributes(this.attributes(identity, environment));
  }
}

export type { AppIdentity };
export { appIdentitySchema, ResourceIdentityMapper };
