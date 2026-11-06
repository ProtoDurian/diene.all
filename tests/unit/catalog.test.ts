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

describe('generic problem catalog', () => {
  it('should ship exactly the six portable baseline problems', () => {
    // Arrange
    const generics = [ValidationError, EntityNotFound, Conflict, Unauthenticated, Unauthorized, InvalidJson];

    // Act
    const actual = generics.map(({ id, status, recoverable, version }) => ({ id, status, recoverable, version }));

    // Assert
    actual.should.eql([
      { id: 'validation_error', status: 400, recoverable: true, version: 'v1' },
      { id: 'entity_not_found', status: 404, recoverable: false, version: 'v1' },
      { id: 'conflict', status: 409, recoverable: true, version: 'v1' },
      { id: 'unauthenticated', status: 401, recoverable: true, version: 'v1' },
      { id: 'unauthorized', status: 403, recoverable: false, version: 'v1' },
      { id: 'invalid_json', status: 400, recoverable: true, version: 'v1' },
    ]);
  });

  it('should give conflict the same entity reference data as entity_not_found', () => {
    // Arrange
    const schemas = new ProblemSchemaRenderer();
    const registry = new ProblemRegistry(portal);
    const generics = new GenericProblemCatalog().registerGenericProblems(registry);

    // Act
    const conflict = schemas.problemDataJsonSchema(generics.Conflict);
    const notFound = schemas.problemDataJsonSchema(generics.EntityNotFound);

    // Assert
    conflict.should.eql(notFound);
    Conflict.dataSchema.safeParse({ entityType: 'Note', id: '42' }).success.should.be.true();
    Conflict.dataSchema.safeParse({ entityType: 'Note', id: '42', extra: 1 }).success.should.be.false();
  });

  it('should accept validation issues and empty data for the data-less generics', () => {
    // Arrange
    const issues = {
      issues: [
        { path: ['title'], message: 'Required' },
        { path: [], message: 'Bad', code: 'x' },
      ],
    };

    // Act
    const validation = ValidationError.dataSchema.safeParse(issues).success;
    const dataLess = [Unauthenticated, Unauthorized, InvalidJson].map(problem => ({
      empty: problem.dataSchema.safeParse({}).success,
      extra: problem.dataSchema.safeParse({ reason: 'x' }).success,
    }));

    // Assert
    validation.should.be.true();
    dataLess.should.eql([
      { empty: true, extra: false },
      { empty: true, extra: false },
      { empty: true, extra: false },
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
    const forged = { ...genuine, title: 'Forged', status: 599, recoverable: true, dataSchema: z.object({}) };

    // Act
    const actual = catalog.declare(forged, { endpoints: [{ method: 'GET', path: '/notes/{id}' }] });

    // Assert
    actual.title.should.equal('Entity Not Found');
    actual.status.should.equal(404);
    actual.recoverable.should.be.false();
    actual.data.should.eql(new ProblemSchemaRenderer().problemDataJsonSchema(genuine));
    Object.isFrozen(actual.endpoints[0]).should.be.true();
  });

  it('should reject duplicates, foreign problems, and malformed endpoints', () => {
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
    const method = thrown(() =>
      catalog.declare(registry.require('conflict'), { endpoints: [{ method: 'post', path: '/n' }] }),
    );
    const path = thrown(() =>
      catalog.declare(registry.require('conflict'), { endpoints: [{ method: 'POST', path: 'n' }] }),
    );

    // Assert
    duplicate.code.should.equal('duplicate');
    foreignError.code.should.equal('unknown');
    method.should.be.instanceOf(RangeError);
    path.should.be.instanceOf(RangeError);
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
    resource.metadata.should.eql({ name: 'zinc-api-raichu-v1', namespace: 'nitroso' });
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
      schema: new ProblemSchemaRenderer().problemDataJsonSchema(generic),
      endpoints: [{ method: 'GET', path: '/notes' }],
    });
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
});
