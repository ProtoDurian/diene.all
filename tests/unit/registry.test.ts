import { describe, it } from 'bun:test';
import { ProblemFactory, ProblemRegistry, ProblemRegistryError, ProblemStatusPolicy } from '@atomicloud/diene.problems';
import 'should';
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

describe('ProblemRegistry', () => {
  it('should bind the versioned type URI and keep the definition fields', () => {
    // Arrange
    const registry = new ProblemRegistry(portal);

    // Act
    const actual = registry.register(definition);

    // Assert
    actual.type.should.equal('https://errors.atomi.cloud/docs/raichu/nitroso/zinc/api/v1/note_locked');
    actual.recoverable.should.be.true();
    Object.isFrozen(actual).should.be.true();
    registry.get('note_locked', 'v1')!.should.equal(actual);
    registry.require('note_locked').should.equal(actual);
  });

  it('should enumerate by version, then by id', () => {
    // Arrange
    const registry = new ProblemRegistry(portal);
    const later = registry.register({ ...definition, id: 'alpha', version: 'v2' });
    const second = registry.register({ ...definition, id: 'zulu' });
    const first = registry.register({ ...definition, id: 'beta' });

    // Act
    const actual = registry.list();

    // Assert
    actual.should.eql([first, second, later]);
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
    const badStatus = registry.tryRegister({ ...definition, id: 'bad_status', status: 99 });
    const badTitle = registry.tryRegister({ ...definition, id: 'bad_title', title: ' ' });
    const badId = registry.tryRegister({ ...definition, id: 'BadId' });

    // Assert
    (await first.isOk()).should.be.true();
    (await duplicate.unwrapErr()).code.should.equal('duplicate');
    (await badStatus.unwrapErr()).message.should.startWith('Problem status must be');
    (await badTitle.unwrapErr()).message.should.equal('Problem title must not be empty');
    const invalidId = await badId.unwrapErr();
    invalidId.code.should.equal('invalid');
    (invalidId.cause as Error).should.be.instanceOf(RangeError);
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

  it('should reject invalid data and an out-of-range status override', () => {
    // Arrange
    const registered = new ProblemRegistry(portal).register(definition);
    const factory = new ProblemFactory();

    // Act
    const badData = thrown(() => factory.createProblem(registered, { data: { id: 42 } as never }));
    const badStatus = thrown(() => factory.createProblem(registered, { status: 600, data: { id: '42' } }));

    // Assert
    badData.should.be.instanceOf(z.ZodError);
    badStatus.should.be.instanceOf(ProblemRegistryError);
    badStatus.message.should.equal('Problem status override must be an integer from 100 through 599; received 600');
  });
});

describe('ProblemStatusPolicy', () => {
  it('should accept only integer HTTP statuses from 100 through 599', () => {
    // Arrange
    const policy = new ProblemStatusPolicy();
    const values: readonly unknown[] = [100, 599, 99, 600, 404.5, '404'];

    // Act
    const actual = values.map(value => policy.isStatus(value));

    // Assert
    actual.should.eql([true, true, false, false, false, false]);
  });
});
