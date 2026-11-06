import { slugify } from '@atomicloud/diene.core-utils';
import { z } from 'zod';
import { ProblemSchemaRenderer } from './publish.js';
import { ProblemRegistry, ProblemRegistryError } from './registry.js';
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

const GENERIC_VERSION = 'v1';
const ENDPOINT_METHOD_PATTERN = /^[A-Z]+$/;
const ENTITY_REFERENCE_SCHEMA = z.object({ entityType: z.string(), id: z.string() }).strict();
const NO_DATA_SCHEMA = z.object({}).strict();

export const ValidationError = Object.freeze({
  id: 'validation_error',
  title: 'Validation Error',
  status: 400,
  recoverable: true,
  version: GENERIC_VERSION,
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
  version: GENERIC_VERSION,
  dataSchema: ENTITY_REFERENCE_SCHEMA,
});

export const Conflict = Object.freeze({
  id: 'conflict',
  title: 'Conflict',
  status: 409,
  recoverable: true,
  version: GENERIC_VERSION,
  dataSchema: ENTITY_REFERENCE_SCHEMA,
});

export const Unauthenticated = Object.freeze({
  id: 'unauthenticated',
  title: 'Unauthenticated',
  status: 401,
  recoverable: true,
  version: GENERIC_VERSION,
  dataSchema: NO_DATA_SCHEMA,
});

export const Unauthorized = Object.freeze({
  id: 'unauthorized',
  title: 'Unauthorized',
  status: 403,
  recoverable: false,
  version: GENERIC_VERSION,
  dataSchema: NO_DATA_SCHEMA,
});

export const InvalidJson = Object.freeze({
  id: 'invalid_json',
  title: 'Invalid JSON',
  status: 400,
  recoverable: true,
  version: GENERIC_VERSION,
  dataSchema: NO_DATA_SCHEMA,
});

export class GenericProblemCatalog {
  // biome-ignore lint/complexity/noUselessConstructor: Bun coverage counts an implicit constructor as an uncovered function
  constructor() {}

  registerGenericProblems(registry: ProblemRegistry) {
    return Object.freeze({
      ValidationError: registry.register(ValidationError),
      EntityNotFound: registry.register(EntityNotFound),
      Conflict: registry.register(Conflict),
      Unauthenticated: registry.register(Unauthenticated),
      Unauthorized: registry.register(Unauthorized),
      InvalidJson: registry.register(InvalidJson),
    });
  }

  createGenericProblemRegistry(portal: ErrorPortalConfig): ProblemRegistry {
    const registry = new ProblemRegistry(portal);
    this.registerGenericProblems(registry);
    return registry;
  }
}

export class ProblemCatalog {
  readonly #entries = new Map<string, ProblemCatalogEntry>();

  constructor(
    readonly registry: ProblemRegistry,
    private readonly schemas: ProblemSchemaRenderer = new ProblemSchemaRenderer(),
  ) {}

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
      data: this.schemas.problemDataJsonSchema(registered),
      endpoints: declaration.endpoints.map(endpoint => this.validateEndpoint(endpoint)),
    });
    this.#entries.set(entry.id, entry);
    return entry;
  }

  list(): readonly ProblemCatalogEntry[] {
    return [...this.#entries.values()].sort((left, right) => left.id.localeCompare(right.id));
  }

  private validateEndpoint(endpoint: ProblemEndpoint): ProblemEndpoint {
    if (!ENDPOINT_METHOD_PATTERN.test(endpoint.method)) {
      throw new RangeError(`Problem endpoint method must be uppercase; received ${endpoint.method}`);
    }
    if (!endpoint.path.startsWith('/')) {
      throw new RangeError(`Problem endpoint path must start with '/'; received ${endpoint.path}`);
    }
    return Object.freeze({ method: endpoint.method, path: endpoint.path });
  }
}

export class ProblemResourceEmitter {
  constructor(private readonly uris: ProblemTypeUriBuilder = new ProblemTypeUriBuilder()) {}

  emitProblemResource(catalog: ProblemCatalog, identity: ProblemResourceIdentity): ProblemResource {
    const entries = catalog.list();
    if (entries.length === 0) {
      throw new RangeError('Problem resource needs at least one declared catalog entry');
    }
    const portal: ErrorPortalConfig = {
      ...catalog.registry.portal,
      platform: identity.platform,
      service: identity.service,
      module: identity.module,
      landscape: identity.landscape,
    };
    for (const entry of entries) {
      const expected = this.uris.buildProblemTypeUri(portal, identity.version, entry.id);
      if (entry.type !== expected) {
        throw new RangeError(`Problem ${entry.type} does not belong to the resource row ${expected}`);
      }
    }

    const { platform, service, module, landscape, version } = identity;
    return {
      apiVersion: 'atomi.cloud/v1alpha1',
      kind: 'Problem',
      metadata: {
        name: [service, module, landscape, version].map(slugify).join('-'),
        namespace: platform,
      },
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
