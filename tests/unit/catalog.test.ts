import { describe, expect, it } from 'bun:test';
import {
  Conflict,
  EntityNotFound,
  GenericProblemCatalog,
  InvalidJson,
  ProblemCatalog,
  ProblemFactory,
  ProblemManifestEmitter,
  ProblemRegistry,
  ProblemRegistryError,
  ProblemResourceEmitter,
  ProblemSchemaRenderer,
  Unauthenticated,
  Unauthorized,
  ValidationError,
} from '@atomicloud/diene.problems';
import 'should';
import { z } from 'zod';
import { portal, thrown } from './support/fixtures';

const row = Object.freeze({ platform: 'nitroso', service: 'zinc', module: 'api', landscape: 'raichu', version: 'v1' });

const noteLocked = Object.freeze({
  id: 'note_locked',
  title: 'Note Locked',
  status: 423,
  recoverable: true,
  version: 'v1',
  dataSchema: z.object({ noteId: z.string(), lockedBy: z.string().optional() }).strict(),
});

class FixtureCatalog {
  readonly registry = new GenericProblemCatalog().createGenericProblemRegistry(portal);
  readonly locked = this.registry.register(noteLocked);
  readonly catalog = new ProblemCatalog(this.registry);

  declareAll(): ProblemCatalog {
    this.catalog.declare(this.locked, { endpoints: [{ method: 'PUT', path: '/notes/{id}' }] });
    this.catalog.declare(this.registry.require('validation_error'), {
      endpoints: [
        { method: 'POST', path: '/notes' },
        { method: 'PUT', path: '/notes/{id}' },
      ],
    });
    this.catalog.declare(this.registry.require('entity_not_found'), {
      endpoints: [{ method: 'GET', path: '/notes/{id}' }],
    });
    this.catalog.declare(this.registry.require('conflict'), { endpoints: [{ method: 'POST', path: '/notes' }] });
    this.catalog.declare(this.registry.require('unauthenticated'), { endpoints: [{ method: 'GET', path: '/notes' }] });
    this.catalog.declare(this.registry.require('unauthorized'), { endpoints: [{ method: 'GET', path: '/notes' }] });
    this.catalog.declare(this.registry.require('invalid_json'), { endpoints: [{ method: 'POST', path: '/notes' }] });
    return this.catalog;
  }
}

class RowCatalog {
  build(config: typeof portal): ProblemCatalog {
    const registry = new GenericProblemCatalog().createGenericProblemRegistry(config);
    const catalog = new ProblemCatalog(registry);
    catalog.declare(registry.require('conflict'), { endpoints: [] });
    return catalog;
  }
}

describe('generic problem catalog', () => {
  it('should ship exactly the six portable baseline problems', () => {
    // Arrange
    const generics = [ValidationError, EntityNotFound, Conflict, Unauthenticated, Unauthorized, InvalidJson];

    // Act
    const actual = generics.map(({ id, status, recoverable }) => ({ id, status, recoverable }));

    // Assert
    actual.should.eql([
      { id: 'validation_error', status: 400, recoverable: true },
      { id: 'entity_not_found', status: 404, recoverable: false },
      { id: 'conflict', status: 409, recoverable: true },
      { id: 'unauthenticated', status: 401, recoverable: true },
      { id: 'unauthorized', status: 403, recoverable: false },
      { id: 'invalid_json', status: 400, recoverable: true },
    ]);
  });

  it('should give conflict the same entity reference data as entity_not_found', () => {
    // Arrange
    const registry = new ProblemRegistry(portal);

    // Act
    const generics = new GenericProblemCatalog().registerGenericProblems(registry);

    // Assert
    generics.Conflict.schema.should.eql(generics.EntityNotFound.schema);
    Conflict.dataSchema.safeParse({ entityType: 'Note', id: '42' }).success.should.be.true();
    Conflict.dataSchema.safeParse({ entityType: 'Note', id: '42', extra: 1 }).success.should.be.false();
  });

  it('should accept validation issues and leave the data-less generics without a schema', () => {
    // Arrange
    const issues = {
      issues: [
        { path: ['title'], message: 'Required' },
        { path: [], message: 'Bad', code: 'x' },
      ],
    };
    const renderer = new ProblemSchemaRenderer();

    // Act
    const validation = ValidationError.dataSchema.safeParse(issues).success;
    const dataLess = [Unauthenticated, Unauthorized, InvalidJson].map(problem =>
      renderer.problemDataJsonSchema({ ...problem, version: 'v1' }),
    );

    // Assert
    validation.should.be.true();
    for (const problem of [Unauthenticated, Unauthorized, InvalidJson]) {
      problem.should.not.have.property('dataSchema');
    }
    dataLess.should.eql([
      { $schema: 'http://json-schema.org/draft-07/schema#', not: {} },
      { $schema: 'http://json-schema.org/draft-07/schema#', not: {} },
      { $schema: 'http://json-schema.org/draft-07/schema#', not: {} },
    ]);
  });

  it('should register every generic with a versioned type URI in the service registry', () => {
    // Arrange
    const catalog = new GenericProblemCatalog();

    // Act
    const registry = catalog.createGenericProblemRegistry(portal);

    // Assert
    registry
      .list()
      .map(problem => problem.type)
      .should.eql(
        ['conflict', 'entity_not_found', 'invalid_json', 'unauthenticated', 'unauthorized', 'validation_error'].map(
          id => `https://errors.atomi.cloud/docs/raichu/nitroso/zinc/api/v1/${id}`,
        ),
      );
  });

  it('should register the generics at the requested version with fixed ids, statuses, and flags', () => {
    // Arrange
    const catalog = new GenericProblemCatalog();

    // Act
    const registry = catalog.createGenericProblemRegistry(portal, 'v2');

    // Assert
    registry
      .list()
      .map(({ id, status, recoverable, version }) => `${version}/${id}/${status}/${recoverable}`)
      .should.eql([
        'v2/conflict/409/true',
        'v2/entity_not_found/404/false',
        'v2/invalid_json/400/true',
        'v2/unauthenticated/401/true',
        'v2/unauthorized/403/false',
        'v2/validation_error/400/true',
      ]);
  });

  it('should build the generic registry with the injected URI builder', () => {
    // Arrange
    const uris = { buildProblemTypeUri: (_: unknown, version: string, id: string) => `urn:${version}:${id}` };

    // Act
    const registry = new GenericProblemCatalog(uris as never).createGenericProblemRegistry(portal);

    // Assert
    registry.require('conflict').type.should.equal('urn:v1:conflict');
  });

  it('should share one id namespace with service problems', () => {
    // Arrange
    const registry = new GenericProblemCatalog().createGenericProblemRegistry(portal);

    // Act
    const clash = thrown(() => registry.register({ ...noteLocked, id: 'conflict' })) as ProblemRegistryError;

    // Assert
    clash.code.should.equal('duplicate');
  });
});

describe('ProblemManifestEmitter', () => {
  it('should snapshot the enumerable list and a schema keyed by every type URI', () => {
    // Arrange
    const { registry } = new FixtureCatalog();
    const emitter = new ProblemManifestEmitter();

    // Act
    const manifest = emitter.emitProblemManifest(registry);

    // Assert
    manifest.problems.length.should.equal(7);
    Object.keys(manifest.schemas).length.should.equal(7);
    expect(manifest).toMatchSnapshot();
  });
});

describe('ProblemCatalog', () => {
  it('should take every catalog field from the registry, not the caller', () => {
    // Arrange
    const { registry, catalog } = new FixtureCatalog();
    const genuine = registry.require('entity_not_found');
    const forged = { ...genuine, title: 'Forged', status: 599, recoverable: true, schema: {} };

    // Act
    const actual = catalog.declare(forged, { endpoints: [{ method: 'GET', path: '/notes/{id}' }] });

    // Assert
    actual.title.should.equal('Entity Not Found');
    actual.status.should.equal(404);
    actual.recoverable.should.be.false();
    actual.data.should.eql(genuine.schema);
    Object.isFrozen(actual.endpoints[0]).should.be.true();
  });

  it('should reject duplicate declarations and foreign problems', () => {
    // Arrange
    const { registry, catalog } = new FixtureCatalog();
    const notFound = registry.require('entity_not_found');
    catalog.declare(notFound, { endpoints: [] });
    const foreign = new GenericProblemCatalog().createGenericProblemRegistry({ ...portal, service: 'argon' });

    // Act
    const duplicate = thrown(() => catalog.declare(notFound, { endpoints: [] })) as ProblemRegistryError;
    const foreignError = thrown(() =>
      catalog.declare(foreign.require('conflict'), { endpoints: [] }),
    ) as ProblemRegistryError;

    // Assert
    duplicate.code.should.equal('duplicate');
    foreignError.code.should.equal('unknown');
  });

  it('should reject non-HTTP methods, relative paths, and duplicate endpoints', () => {
    // Arrange
    const { registry } = new FixtureCatalog();
    const conflict = registry.require('conflict');
    const declare = (endpoints: { method: string; path: string }[]) => () =>
      new ProblemCatalog(registry).declare(conflict, { endpoints });

    // Act
    const lower = thrown(declare([{ method: 'post', path: '/n' }]));
    const unknown = thrown(declare([{ method: 'FOO', path: '/n' }]));
    const relative = thrown(declare([{ method: 'POST', path: 'n' }]));
    const duplicate = thrown(
      declare([
        { method: 'GET', path: '/a' },
        { method: 'GET', path: '/a' },
      ]),
    );

    // Assert
    lower.message.should.startWith('Problem endpoint method must be an uppercase HTTP method');
    unknown.message.should.startWith('Problem endpoint method must be an uppercase HTTP method');
    relative.message.should.startWith("Problem endpoint path must start with '/'");
    duplicate.message.should.equal('Problem endpoint GET /a is declared twice');
  });
});

describe('ProblemResourceEmitter', () => {
  it('should snapshot one Problem CR for the fixture row with generic and service entries', () => {
    // Arrange
    const catalog = new FixtureCatalog().declareAll();
    const emitter = new ProblemResourceEmitter();

    // Act
    const resource = emitter.emitProblemResource(catalog, row);

    // Assert
    resource.metadata.should.eql({ name: 'zinc.api.raichu.v1', namespace: 'nitroso' });
    resource.spec.problems
      .map(problem => problem.id)
      .should.eql([
        'conflict',
        'entity_not_found',
        'invalid_json',
        'note_locked',
        'unauthenticated',
        'unauthorized',
        'validation_error',
      ]);
    resource.spec.problems[0]!.should.have.property('schema');
    resource.spec.problems[0]!.should.not.have.property('data');
    expect(resource).toMatchSnapshot();
  });

  it('should emit a generic entry with the same fields the registry holds', () => {
    // Arrange
    const fixture = new FixtureCatalog();
    fixture.declareAll();
    const generic = fixture.registry.require('unauthorized');

    // Act
    const entry = new ProblemResourceEmitter()
      .emitProblemResource(fixture.catalog, row)
      .spec.problems.find(problem => problem.id === 'unauthorized')!;

    // Assert
    entry.should.eql({
      id: 'unauthorized',
      type: generic.type,
      title: 'Unauthorized',
      status: 403,
      recoverable: false,
      schema: generic.schema,
      endpoints: [{ method: 'GET', path: '/notes' }],
    });
  });

  it('should emit a v2 row holding a v2 service problem and the v2 generics', () => {
    // Arrange
    const registry = new GenericProblemCatalog().createGenericProblemRegistry(portal, 'v2');
    const locked = registry.register({ ...noteLocked, version: 'v2' });
    const catalog = new ProblemCatalog(registry);
    catalog.declare(locked, { endpoints: [{ method: 'PUT', path: '/notes/{id}' }] });
    catalog.declare(registry.require('conflict'), { endpoints: [{ method: 'POST', path: '/notes' }] });

    // Act
    const resource = new ProblemResourceEmitter().emitProblemResource(catalog, { ...row, version: 'v2' });

    // Assert
    resource.metadata.name.should.equal('zinc.api.raichu.v2');
    resource.spec.problems
      .map(problem => problem.type)
      .should.eql([
        'https://errors.atomi.cloud/docs/raichu/nitroso/zinc/api/v2/conflict',
        'https://errors.atomi.cloud/docs/raichu/nitroso/zinc/api/v2/note_locked',
      ]);
  });

  it('should give distinct rows distinct names where a slug would collide', () => {
    // Arrange
    const emitter = new ProblemResourceEmitter();
    const rows = new RowCatalog();

    // Act
    const first = emitter.emitProblemResource(rows.build({ ...portal, service: 'a-b', module: 'c' }), {
      ...row,
      service: 'a-b',
      module: 'c',
    });
    const second = emitter.emitProblemResource(rows.build({ ...portal, service: 'a', module: 'b-c' }), {
      ...row,
      service: 'a',
      module: 'b-c',
    });
    const underscore = thrown(() =>
      emitter.emitProblemResource(rows.build({ ...portal, service: 'a_b', module: 'c' }), {
        ...row,
        service: 'a_b',
        module: 'c',
      }),
    );

    // Assert
    first.metadata.name.should.equal('a-b.c.raichu.v1');
    second.metadata.name.should.equal('a.b-c.raichu.v1');
    underscore.message.should.equal('Problem resource service must be a DNS-1123 label; received "a_b"');
  });

  it('should refuse a namespace or identity segment that is not a DNS-1123 label', () => {
    // Arrange
    const emitter = new ProblemResourceEmitter();
    const catalog = new FixtureCatalog().declareAll();
    const identities = [
      { ...row, platform: 'Nitro_So' },
      { ...row, module: 'api.v2' },
      { ...row, landscape: '-raichu' },
      { ...row, service: 'z'.repeat(64) },
      { ...row, version: 'v01' },
    ];

    // Act
    const messages = identities.map(identity => thrown(() => emitter.emitProblemResource(catalog, identity)).message);

    // Assert
    messages.should.eql([
      'Problem resource platform must be a DNS-1123 label; received "Nitro_So"',
      'Problem resource module must be a DNS-1123 label; received "api.v2"',
      'Problem resource landscape must be a DNS-1123 label; received "-raichu"',
      `Problem resource service must be a DNS-1123 label; received "${'z'.repeat(64)}"`,
      'Problem resource version must match /^v[1-9][0-9]*$/; received v01',
    ]);
  });

  it('should refuse a resource name longer than 253 characters', () => {
    // Arrange
    const emitter = new ProblemResourceEmitter();
    const catalog = new FixtureCatalog().declareAll();
    const label = 'a'.repeat(63);
    const identity = { ...row, service: label, module: label, landscape: label, version: `v1${'0'.repeat(60)}` };

    // Act
    const error = thrown(() => emitter.emitProblemResource(catalog, identity));

    // Assert
    error.message.should.startWith('Problem resource name must be at most 253 characters');
  });

  it('should reject an empty catalog and every identity field that drifts from the registry', () => {
    // Arrange
    const empty = new FixtureCatalog().catalog;
    const catalog = new FixtureCatalog().declareAll();
    const emitter = new ProblemResourceEmitter();
    const drifts = [
      { ...row, platform: 'alcohol' },
      { ...row, service: 'argon' },
      { ...row, module: 'web' },
      { ...row, landscape: 'pichu' },
      { ...row, version: 'v2' },
    ];

    // Act
    const emptyError = thrown(() => emitter.emitProblemResource(empty, row));
    const driftErrors = drifts.map(identity => thrown(() => emitter.emitProblemResource(catalog, identity)));

    // Assert
    emptyError.message.should.equal('Problem resource needs at least one declared catalog entry');
    for (const error of driftErrors) {
      error.should.be.instanceOf(RangeError);
      error.message.should.match(/does not belong to the resource row/);
    }
  });

  it('should check rows through the injected URI builder', () => {
    // Arrange
    const catalog = new FixtureCatalog().declareAll();
    const uris = { buildProblemTypeUri: () => 'urn:other' };

    // Act
    const error = thrown(() => new ProblemResourceEmitter(uris as never).emitProblemResource(catalog, row));

    // Assert
    error.message.should.match(/urn:other/);
  });
});

describe('Problem minting from the generic catalog', () => {
  it('should mint a conflict Problem with entity reference data', () => {
    // Arrange
    const registry = new GenericProblemCatalog().createGenericProblemRegistry(portal);

    // Act
    const actual = new ProblemFactory().createProblem(registry.require('conflict'), {
      detail: 'Note 42 changed',
      data: { entityType: 'Note', id: '42' },
    });

    // Assert
    actual.should.eql({
      type: 'https://errors.atomi.cloud/docs/raichu/nitroso/zinc/api/v1/conflict',
      title: 'Conflict',
      status: 409,
      detail: 'Note 42 changed',
      data: { entityType: 'Note', id: '42' },
    });
  });

  it('should mint a data-less generic without a data member', () => {
    // Arrange
    const generics = new GenericProblemCatalog().registerGenericProblems(new ProblemRegistry(portal));

    // Act
    const actual = new ProblemFactory().createProblem(generics.Unauthenticated, {});

    // Assert
    actual.should.eql({
      type: 'https://errors.atomi.cloud/docs/raichu/nitroso/zinc/api/v1/unauthenticated',
      title: 'Unauthenticated',
      status: 401,
    });
  });
});
