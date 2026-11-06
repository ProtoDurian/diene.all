import {
  createProblem,
  EntityNotFound,
  type ErrorPortalConfig,
  type Problem,
  type ProblemDefinition,
  ProblemRegistry,
  type RegisteredProblem,
  ValidationError,
} from '@atomicloud/diene.problems';
import { z } from 'zod';

const VERSION = 'v1';

const InternalError = {
  id: 'internal_error',
  title: 'Internal Error',
  status: 500,
  version: VERSION,
  dataSchema: z.object({}).strict(),
};

const ServiceUnavailable = {
  id: 'service_unavailable',
  title: 'Service Unavailable',
  status: 503,
  version: VERSION,
  dataSchema: z.object({ dependency: z.string() }).strict(),
};

const RouteNotFound = {
  id: 'route_not_found',
  title: 'Route Not Found',
  status: 404,
  version: VERSION,
  dataSchema: z.object({ method: z.string(), path: z.string() }).strict(),
};

const PayloadTooLarge = {
  id: 'payload_too_large',
  title: 'Payload Too Large',
  status: 413,
  version: VERSION,
  dataSchema: z.object({ limitBytes: z.number().int() }).strict(),
};

export interface ValidationIssue {
  readonly path: readonly PropertyKey[];
  readonly message: string;
  readonly code?: string;
}

export type ProblemIdentity = Pick<ErrorPortalConfig, 'landscape' | 'platform' | 'service' | 'module'>;

export class ProblemPortal {
  constructor(
    private readonly identity: ProblemIdentity = {
      landscape: 'app',
      platform: 'aseity',
      service: 'api',
      module: 'core',
    },
  ) {}

  /** Problem type URIs live under the app's own origin. */
  config(appUrl: string): ErrorPortalConfig {
    const url = new URL(appUrl);
    return { scheme: url.protocol === 'http:' ? 'http' : 'https', host: url.host, ...this.identity };
  }

  registry(appUrl: string): ProblemRegistry {
    return new ProblemRegistry(this.config(appUrl));
  }
}

export class ApiProblems {
  private readonly validation: RegisteredProblem<typeof ValidationError.dataSchema>;
  private readonly notFound: RegisteredProblem<typeof EntityNotFound.dataSchema>;
  private readonly internal: RegisteredProblem<typeof InternalError.dataSchema>;
  private readonly unavailable: RegisteredProblem<typeof ServiceUnavailable.dataSchema>;
  private readonly route: RegisteredProblem<typeof RouteNotFound.dataSchema>;
  private readonly tooLarge: RegisteredProblem<typeof PayloadTooLarge.dataSchema>;

  constructor(registry: ProblemRegistry) {
    this.validation = this.ensure(registry, { ...ValidationError, version: VERSION });
    this.notFound = this.ensure(registry, { ...EntityNotFound, version: VERSION });
    this.internal = this.ensure(registry, InternalError);
    this.unavailable = this.ensure(registry, ServiceUnavailable);
    this.route = this.ensure(registry, RouteNotFound);
    this.tooLarge = this.ensure(registry, PayloadTooLarge);
  }

  invalid(issues: readonly ValidationIssue[]): Response {
    return this.respond(
      createProblem(this.validation, {
        detail: 'The request did not pass validation.',
        data: {
          issues: issues.map(issue => ({
            path: issue.path.map(String),
            message: issue.message,
            ...(issue.code === undefined ? {} : { code: issue.code }),
          })),
        },
      }),
    );
  }

  entityNotFound(entityType: string, id: string): Response {
    return this.respond(
      createProblem(this.notFound, { detail: `No ${entityType} ${id} in this tenant.`, data: { entityType, id } }),
    );
  }

  internalError(): Response {
    return this.respond(createProblem(this.internal, { detail: 'An unexpected error occurred.', data: {} }));
  }

  serviceUnavailable(dependency: string): Response {
    return this.respond(
      createProblem(this.unavailable, { detail: `${dependency} is unavailable.`, data: { dependency } }),
    );
  }

  routeNotFound(method: string, path: string): Response {
    return this.respond(createProblem(this.route, { data: { method, path } }));
  }

  payloadTooLarge(limitBytes: number): Response {
    return this.respond(createProblem(this.tooLarge, { data: { limitBytes } }));
  }

  private respond(problem: Problem): Response {
    return new Response(JSON.stringify(problem), {
      status: problem.status,
      headers: { 'content-type': 'application/problem+json' },
    });
  }

  // The registry is shared with the auth module, so an id it registered first is reused.
  private ensure<TSchema extends z.ZodType>(
    registry: ProblemRegistry,
    definition: ProblemDefinition<TSchema>,
  ): RegisteredProblem<TSchema> {
    return (
      (registry.get(definition.id, definition.version) as RegisteredProblem<TSchema> | undefined) ??
      registry.register(definition)
    );
  }
}
