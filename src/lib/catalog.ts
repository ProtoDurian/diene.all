import { z } from 'zod';
import { ProblemSchemaRenderer } from './publish.js';
import { ProblemRegistry, ProblemRegistryError, ProblemStatusPolicy } from './registry.js';
import type {
  ErrorPortalConfig,
  ProblemCatalogDeclaration,
  ProblemCatalogEntry,
  ProblemEndpoint,
  ProblemResource,
  ProblemResourceIdentity,
  RegisteredProblem,
} from './types.js';
import { ProblemTypeUriBuilder } from './uri.js';

const HTTP_METHODS: readonly string[] = Object.freeze([
  'GET',
  'HEAD',
  'POST',
  'PUT',
  'PATCH',
  'DELETE',
  'OPTIONS',
  'TRACE',
  'CONNECT',
]);
const DNS_LABEL_PATTERN = /^[a-z0-9]([-a-z0-9]*[a-z0-9])?$/;
const DNS_LABEL_MAX = 63;
const RESOURCE_NAME_MAX = 253;
const RESOURCE_VERSION_PATTERN = /^v[1-9][0-9]*$/;
const ENTITY_REFERENCE_SCHEMA = z.object({ entityType: z.string(), id: z.string() }).strict();

export const ValidationError = Object.freeze({
  id: 'validation_error',
  title: 'Validation Error',
  status: 400,
  recoverable: true,
  dataSchema: z
    .object({
      issues: z.array(
        z
          .object({
            path: z.array(z.string()),
            message: z.string(),
            code: z.string().optional(),
          })
          .strict(),
      ),
    })
    .strict(),
});

export const EntityNotFound = Object.freeze({
  id: 'entity_not_found',
  title: 'Entity Not Found',
  status: 404,
  recoverable: false,
  dataSchema: ENTITY_REFERENCE_SCHEMA,
});

export const Conflict = Object.freeze({
  id: 'conflict',
  title: 'Conflict',
  status: 409,
  recoverable: true,
  dataSchema: ENTITY_REFERENCE_SCHEMA,
});

export const Unauthenticated = Object.freeze({
  id: 'unauthenticated',
  title: 'Unauthenticated',
  status: 401,
  recoverable: true,
});

export const Unauthorized = Object.freeze({
  id: 'unauthorized',
  title: 'Unauthorized',
  status: 403,
  recoverable: false,
});

export const InvalidJson = Object.freeze({
  id: 'invalid_json',
  title: 'Invalid JSON',
  status: 400,
  recoverable: true,
});

export class GenericProblemCatalog {
  constructor(
    private readonly uris: ProblemTypeUriBuilder = new ProblemTypeUriBuilder(),
    private readonly statuses: ProblemStatusPolicy = new ProblemStatusPolicy(),
    private readonly schemas: ProblemSchemaRenderer = new ProblemSchemaRenderer(),
  ) {}

  registerGenericProblems(registry: ProblemRegistry, version = 'v1') {
    return Object.freeze({
      ValidationError: registry.register({ ...ValidationError, version }),
      EntityNotFound: registry.register({ ...EntityNotFound, version }),
      Conflict: registry.register({ ...Conflict, version }),
      Unauthenticated: registry.register({ ...Unauthenticated, version }),
      Unauthorized: registry.register({ ...Unauthorized, version }),
      InvalidJson: registry.register({ ...InvalidJson, version }),
    });
  }

  createGenericProblemRegistry(portal: ErrorPortalConfig, version = 'v1'): ProblemRegistry {
    const registry = new ProblemRegistry(portal, this.uris, this.statuses, this.schemas);
    this.registerGenericProblems(registry, version);
    return registry;
  }
}

export class ProblemCatalog {
  readonly #entries = new Map<string, ProblemCatalogEntry>();

  constructor(readonly registry: ProblemRegistry) {}

  declare(problem: RegisteredProblem, declaration: ProblemCatalogDeclaration): ProblemCatalogEntry {
    const registered = this.registry.get(problem.id, problem.version);
    if (registered?.type !== problem.type) {
      throw new ProblemRegistryError('unknown', `Problem ${problem.id} does not belong to this catalog registry`);
    }
    if (this.#entries.has(registered.id)) {
      throw new ProblemRegistryError('duplicate', `Problem ${registered.id} is already declared in the catalog`);
    }

    const entry: ProblemCatalogEntry = Object.freeze({
      id: registered.id,
      type: registered.type,
      title: registered.title,
      status: registered.status,
      recoverable: registered.recoverable,
      version: registered.version,
      data: registered.schema,
      endpoints: this.validateEndpoints(declaration.endpoints),
    });
    this.#entries.set(entry.id, entry);
    return entry;
  }

  list(): readonly ProblemCatalogEntry[] {
    return [...this.#entries.values()].sort((left, right) => left.id.localeCompare(right.id));
  }

  private validateEndpoints(endpoints: readonly ProblemEndpoint[]): readonly ProblemEndpoint[] {
    const seen = new Set<string>();
    return endpoints.map(({ method, path }) => {
      if (!HTTP_METHODS.includes(method)) {
        throw new RangeError(`Problem endpoint method must be an uppercase HTTP method; received ${method}`);
      }
      if (!path.startsWith('/')) {
        throw new RangeError(`Problem endpoint path must start with '/'; received ${path}`);
      }
      const key = `${method} ${path}`;
      if (seen.has(key)) {
        throw new RangeError(`Problem endpoint ${key} is declared twice`);
      }
      seen.add(key);
      return Object.freeze({ method, path });
    });
  }
}

export class ProblemResourceEmitter {
  constructor(private readonly uris: ProblemTypeUriBuilder = new ProblemTypeUriBuilder()) {}

  emitProblemResource(catalog: ProblemCatalog, identity: ProblemResourceIdentity): ProblemResource {
    const { platform, service, module, landscape, version } = identity;
    const registryPortal = catalog.registry.portal;
    if (registryPortal.scheme !== 'https') {
      throw new RangeError(`Problem resource needs an https ErrorPortal; received ${registryPortal.scheme}`);
    }
    for (const [field, value] of Object.entries({ platform, service, module, landscape })) {
      if (typeof value !== 'string' || value.length > DNS_LABEL_MAX || !DNS_LABEL_PATTERN.test(value)) {
        throw new RangeError(`Problem resource ${field} must be a DNS-1123 label; received ${JSON.stringify(value)}`);
      }
      if (registryPortal[field as keyof ErrorPortalConfig] !== value) {
        throw new RangeError(`Problem resource ${field} ${value} does not match the registry ErrorPortal`);
      }
    }
    if (typeof version !== 'string' || !RESOURCE_VERSION_PATTERN.test(version)) {
      throw new RangeError(`Problem resource version must match ${RESOURCE_VERSION_PATTERN}; received ${version}`);
    }
    const name = [service, module, landscape, version].join('.');
    if (name.length > RESOURCE_NAME_MAX) {
      throw new RangeError(`Problem resource name must be at most ${RESOURCE_NAME_MAX} characters; received ${name}`);
    }

    const entries = catalog.list();
    for (const entry of entries) {
      const expected = this.uris.buildProblemTypeUri(registryPortal, version, entry.id);
      if (entry.type !== expected) {
        throw new RangeError(`Problem ${entry.type} does not belong to the resource row ${expected}`);
      }
    }

    return {
      apiVersion: 'atomi.cloud/v1alpha1',
      kind: 'Problem',
      metadata: { name, namespace: platform },
      spec: {
        platform,
        service,
        module,
        landscape,
        version,
        problems: entries.map(entry => ({
          id: entry.id,
          type: entry.type,
          title: entry.title,
          status: entry.status,
          recoverable: entry.recoverable,
          schema: entry.data,
          endpoints: entry.endpoints,
        })),
      },
    };
  }
}
