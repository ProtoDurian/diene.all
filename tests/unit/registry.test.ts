import { describe, it } from 'bun:test';
import { ProblemFactory, ProblemRegistry, ProblemRegistryError, ProblemStatusPolicy } from '@atomicloud/diene.problems';
import should from 'should';
import { z } from 'zod';
import { portal, thrown } from './support/fixtures';

const definition = Object.freeze({
  id: 'note_locked',
  title: 'Note Locked',
  status: 423,
  recoverable: true,
  version: 'v1',
  dataSchema: z.object({ id: z.string() }).strict(),
});

const dataless = Object.freeze({
  id: 'note_archived',
  title: 'Note Archived',
  status: 410,
  recoverable: false,
  version: 'v1',
});

describe('ProblemRegistry', () => {
  it('should bind the versioned type URI, the rendered data schema, and the definition fields', () => {
    // Arrange
    const registry = new ProblemRegistry(portal);

    // Act
    const actual = registry.register(definition);

    // Assert
    actual.type.should.equal('https://errors.atomi.cloud/docs/raichu/nitroso/zinc/api/v1/note_locked');
    actual.recoverable.should.be.true();
    actual.schema.should.have.property('required', ['id']);
    Object.isFrozen(actual).should.be.true();
    registry.get('note_locked', 'v1')!.should.equal(actual);
    registry.require('note_locked').should.equal(actual);
  });

  it('should register a problem without a data schema', () => {
    // Arrange
    const registry = new ProblemRegistry(portal);

    // Act
    const actual = registry.register(dataless);

    // Assert
    should(actual.dataSchema).be.undefined();
    actual.schema.should.eql({ $schema: 'http://json-schema.org/draft-07/schema#', not: {} });
  });

  it('should enumerate by numeric version, then by id', () => {
    // Arrange
    const registry = new ProblemRegistry(portal);
    const tenth = registry.register({ ...definition, id: 'alpha', version: 'v10' });
    const second = registry.register({ ...definition, id: 'alpha', version: 'v2' });
    const firstZulu = registry.register({ ...definition, id: 'zulu' });
    const firstBeta = registry.register({ ...definition, id: 'beta' });

    // Act
    const actual = registry.list();

    // Assert
    actual.should.eql([firstBeta, firstZulu, second, tenth]);
  });

  it('should freeze a copy of the ErrorPortal config', () => {
    // Arrange
    const config = { ...portal };

    // Act
    const registry = new ProblemRegistry(config);
    (config as { service: string }).service = 'argon';

    // Assert
    registry.portal.service.should.equal('zinc');
    Object.isFrozen(registry.portal).should.be.true();
  });

  it('should throw precise errors for duplicates, unknown ids, and ambiguous lookups', () => {
    // Arrange
    const registry = new ProblemRegistry(portal);
    registry.register(definition);
    registry.register({ ...definition, version: 'v2' });

    // Act
    const duplicate = thrown(() => registry.register(definition)) as ProblemRegistryError;
    const unknown = thrown(() => registry.require('missing')) as ProblemRegistryError;
    const unknownVersion = thrown(() => registry.require('note_locked', 'v9')) as ProblemRegistryError;
    const ambiguous = thrown(() => registry.get('note_locked')) as ProblemRegistryError;

    // Assert
    duplicate.code.should.equal('duplicate');
    unknown.code.should.equal('unknown');
    unknown.message.should.equal('Problem id missing is not registered');
    unknownVersion.message.should.equal('Problem id note_locked is not registered for version v9');
    ambiguous.code.should.equal('invalid');
    ambiguous.should.be.instanceOf(ProblemRegistryError);
    ambiguous.name.should.equal('ProblemRegistryError');
  });

  it('should return Result values from tryRegister', async () => {
    // Arrange
    const registry = new ProblemRegistry(portal);

    // Act
    const first = registry.tryRegister(definition);
    const duplicate = registry.tryRegister(definition);
    const lowStatus = registry.tryRegister({ ...definition, id: 'low_status', status: 99 });
    const successStatus = registry.tryRegister({ ...definition, id: 'success_status', status: 200 });
    const badTitle = registry.tryRegister({ ...definition, id: 'bad_title', title: ' ' });
    const badId = registry.tryRegister({ ...definition, id: 'BadId' });

    // Assert
    (await first.isOk()).should.be.true();
    (await duplicate.unwrapErr()).code.should.equal('duplicate');
    (await lowStatus.unwrapErr()).message.should.startWith('Problem status must be an integer from 400 through 599');
    (await successStatus.unwrapErr()).code.should.equal('invalid');
    (await badTitle.unwrapErr()).message.should.equal('Problem title must not be empty');
    const invalidId = await badId.unwrapErr();
    invalidId.code.should.equal('invalid');
    (invalidId.cause as Error).should.be.instanceOf(RangeError);
  });

  it('should refuse at register time a data schema JSON Schema cannot express', async () => {
    // Arrange
    const registry = new ProblemRegistry(portal);

    // Act
    const actual = await registry.tryRegister({ ...definition, dataSchema: z.object({ at: z.date() }) }).unwrapErr();

    // Assert
    actual.code.should.equal('invalid');
    actual.message.should.equal('Invalid problem definition note_locked');
    registry.list().length.should.equal(0);
  });

  it('should build URIs through the injected builder', () => {
    // Arrange
    const uris = { buildProblemTypeUri: () => 'urn:test:problem' };

    // Act
    const actual = new ProblemRegistry(portal, uris as never).register(definition);

    // Assert
    actual.type.should.equal('urn:test:problem');
  });
});

describe('ProblemFactory', () => {
  it('should mint a schema-parsed Problem with optional members only when given', () => {
    // Arrange
    const registered = new ProblemRegistry(portal).register(definition);
    const factory = new ProblemFactory();
    const expected = {
      type: registered.type,
      title: 'Note Locked',
      status: 423,
      detail: 'Note 42 is locked',
      instance: '/notes/42',
      data: { id: '42' },
    };

    // Act
    const actual = factory.createProblem(registered, {
      detail: 'Note 42 is locked',
      instance: '/notes/42',
      data: { id: '42' },
    });
    const bare = factory.createProblem(registered, { status: 409, data: { id: '42' } });

    // Assert
    actual.should.eql(expected);
    bare.should.eql({ type: registered.type, title: 'Note Locked', status: 409, data: { id: '42' } });
  });

  it('should omit data for a problem without a data schema and refuse data passed to it', () => {
    // Arrange
    const registered = new ProblemRegistry(portal).register(dataless);
    const factory = new ProblemFactory();

    // Act
    const actual = factory.createProblem(registered, { detail: 'gone' });
    const withData = thrown(() => factory.createProblem(registered, { data: {} } as never)) as ProblemRegistryError;

    // Assert
    actual.should.eql({ type: registered.type, title: 'Note Archived', status: 410, detail: 'gone' });
    actual.should.not.have.property('data');
    withData.code.should.equal('invalid');
    withData.message.should.equal('Problem note_archived carries no data');
  });

  it('should reject invalid data and a status override outside 400 through 599', () => {
    // Arrange
    const registered = new ProblemRegistry(portal).register(definition);
    const factory = new ProblemFactory();

    // Act
    const badData = thrown(() => factory.createProblem(registered, { data: { id: 42 } as never }));
    const tooHigh = thrown(() => factory.createProblem(registered, { status: 600, data: { id: '42' } }));
    const success = thrown(() => factory.createProblem(registered, { status: 200, data: { id: '42' } }));

    // Assert
    badData.should.be.instanceOf(z.ZodError);
    tooHigh.should.be.instanceOf(ProblemRegistryError);
    tooHigh.message.should.equal('Problem status override must be an integer from 400 through 599; received 600');
    success.message.should.equal('Problem status override must be an integer from 400 through 599; received 200');
  });
});

describe('ProblemStatusPolicy', () => {
  it('should accept only integer error statuses from 400 through 599', () => {
    // Arrange
    const policy = new ProblemStatusPolicy();
    const values: readonly unknown[] = [400, 599, 399, 200, 600, 404.5, '404'];

    // Act
    const actual = values.map(value => policy.isStatus(value));

    // Assert
    actual.should.eql([true, true, false, false, false, false, false]);
  });
});
