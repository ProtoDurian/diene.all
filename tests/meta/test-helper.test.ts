import { describe, it } from 'bun:test';
import {
  type ErrorPortalConfig,
  GenericProblemCatalog,
  type Problem,
  ProblemFactory,
  ProblemRegistryError,
} from '@atomicloud/diene.problems';
import { ProblemAssertionError, ProblemTestHelper } from '@atomicloud/diene.problems/test-helper';
import 'should';

const portal: ErrorPortalConfig = Object.freeze({
  scheme: 'https',
  host: 'errors.atomi.cloud',
  landscape: 'raichu',
  platform: 'nitroso',
  service: 'zinc',
  module: 'api',
});

const registry = new GenericProblemCatalog().createGenericProblemRegistry(portal);
const notFound = registry.require('entity_not_found');

function failureOf(action: () => unknown): ProblemAssertionError {
  try {
    action();
  } catch (error: unknown) {
    return error as ProblemAssertionError;
  }
  throw new Error('expected the matcher to fail');
}

describe('ProblemTestHelper builders', () => {
  it('should build a schema-valid Problem from a registered entry', () => {
    // Arrange
    const helper = new ProblemTestHelper();

    // Act
    const actual = helper.buildProblem(notFound, { instance: '/notes/42', data: { entityType: 'Note', id: '42' } });

    // Assert
    actual.should.eql({
      type: notFound.type,
      title: 'Entity Not Found',
      status: 404,
      instance: '/notes/42',
      data: { entityType: 'Note', id: '42' },
    });
  });

  it('should build from a registry id and version', () => {
    // Arrange
    const helper = new ProblemTestHelper();

    // Act
    const actual = helper.buildProblemFromRegistry(registry, 'unauthorized', {}, 'v1');

    // Assert
    actual.status.should.equal(403);
    actual.type.should.endWith('/v1/unauthorized');
  });

  it('should surface an unknown registry id as a registry error', () => {
    // Arrange
    const helper = new ProblemTestHelper();

    // Act
    const error = failureOf(() => helper.buildProblemFromRegistry(registry, 'missing', {}));

    // Assert
    error.should.be.instanceOf(ProblemRegistryError);
  });

  it('should mint through the injected factory', () => {
    // Arrange
    const factory = new ProblemFactory();
    const minted: Problem[] = [];
    const recording = {
      createProblem: (...args: Parameters<ProblemFactory['createProblem']>) => {
        const problem = factory.createProblem(...args);
        minted.push(problem);
        return problem;
      },
    };
    const helper = new ProblemTestHelper(recording as ProblemFactory);

    // Act
    const actual = helper.buildProblem(notFound, { data: { entityType: 'Note', id: '1' } });

    // Assert
    minted.should.eql([actual]);
  });
});

describe('ProblemExpectation.toBe', () => {
  it('should pass and return the same Problem when it matches the registry entry', () => {
    // Arrange
    const helper = new ProblemTestHelper();
    const expected = helper.buildProblem(notFound, {
      detail: 'missing',
      instance: '/notes/42',
      data: { entityType: 'Note', id: '42' },
    });

    // Act
    const actual = helper.expectProblem(expected).toBe(notFound, {
      status: 404,
      detail: 'missing',
      instance: '/notes/42',
      data: { id: '42', entityType: 'Note' },
    });

    // Assert
    actual.should.equal(expected);
  });

  it('should leave omitted optional expectations unconstrained', () => {
    // Arrange
    const helper = new ProblemTestHelper();
    const expected = helper.buildProblem(notFound, { detail: 'any', data: { entityType: 'Note', id: '42' } });

    // Act
    const actual = helper.expectProblem(expected).toBe(notFound);

    // Assert
    actual.should.equal(expected);
  });

  it('should report every mismatched field in one failure', () => {
    // Arrange
    const helper = new ProblemTestHelper();
    const actual = {
      type: 'https://wrong.example/problem',
      title: 'Wrong',
      status: 500,
      detail: 'wrong detail',
      instance: '/wrong',
      data: { unknown: true },
    };

    // Act
    const error = failureOf(() =>
      helper.expectProblem(actual).toBe(notFound, {
        status: 409,
        detail: 'expected detail',
        instance: '/expected',
        data: { entityType: 'Note', id: '42' },
      }),
    );

    // Assert
    error.should.be.instanceOf(ProblemAssertionError);
    error.name.should.equal('ProblemAssertionError');
    error.differences.length.should.equal(7);
    error.differences[0]!.should.equal(`type expected ${notFound.type}, received https://wrong.example/problem`);
    error.differences[1]!.should.equal('title expected Entity Not Found, received Wrong');
    error.differences[2]!.should.equal('status expected 409, received 500');
    error.differences[3]!.should.equal('detail expected "expected detail", received "wrong detail"');
    error.differences[4]!.should.equal('instance expected "/expected", received "/wrong"');
    error.differences[5]!.should.startWith('data did not match registry schema:');
    error.differences[6]!.should.equal(
      'data expected {\n  "entityType": "Note",\n  "id": "42"\n}, received {\n  "unknown": true\n}',
    );
    error.message.should.startWith('Problem assertion failed:\n- type expected');
  });

  it('should fail on the registry status when no override is given', () => {
    // Arrange
    const helper = new ProblemTestHelper();
    const actual = helper.buildProblem(notFound, { status: 410, data: { entityType: 'Note', id: '42' } });

    // Act
    const error = failureOf(() => helper.expectProblem(actual).toBe(notFound));

    // Assert
    error.differences.should.eql(['status expected 404, received 410']);
  });

  it('should fail when expected detail or instance is absent on the Problem', () => {
    // Arrange
    const helper = new ProblemTestHelper();
    const actual = helper.buildProblem(notFound, { data: { entityType: 'Note', id: '42' } });

    // Act
    const error = failureOf(() => helper.expectProblem(actual).toBe(notFound, { detail: 'x', instance: '/x' }));

    // Assert
    error.differences.should.eql([
      'detail expected "x", received undefined',
      'instance expected "/x", received undefined',
    ]);
  });

  it('should compare schema-valid data exactly', () => {
    // Arrange
    const helper = new ProblemTestHelper();
    const actual = helper.buildProblem(notFound, { data: { entityType: 'Note', id: '42' } });

    // Act
    const error = failureOf(() =>
      helper.expectProblem(actual).toBe(notFound, { data: { entityType: 'Note', id: '43' } }),
    );

    // Assert
    error.differences.should.eql([
      'data expected {\n  "entityType": "Note",\n  "id": "43"\n}, received {\n  "entityType": "Note",\n  "id": "42"\n}',
    ]);
  });

  it('should still fail on data it cannot render as JSON', () => {
    // Arrange
    const helper = new ProblemTestHelper();
    const unauthorized = registry.require('unauthorized');
    const circular: { self?: unknown } = {};
    circular.self = circular;
    const actual = { ...helper.buildProblem(unauthorized, {}), data: circular };

    // Act
    const error = failureOf(() => helper.expectProblem(actual).toBe(unauthorized, { data: {} }));

    // Assert
    error.differences.should.eql([
      'data expected absent, received [object Object]',
      'data expected {}, received [object Object]',
    ]);
  });

  it('should pass a data-less Problem against a data-less entry', () => {
    // Arrange
    const helper = new ProblemTestHelper();
    const unauthorized = registry.require('unauthorized');
    const expected = helper.buildProblem(unauthorized, { detail: 'no access' });

    // Act
    const actual = helper.expectProblem(expected).toBe(unauthorized, { detail: 'no access' });

    // Assert
    actual.should.equal(expected);
    actual.should.not.have.property('data');
  });

  it('should fail with a ProblemAssertionError when given something that is not a Problem', () => {
    // Arrange
    const helper = new ProblemTestHelper();
    const values: readonly unknown[] = [undefined, { ok: true, value: 1 }, { type: 'x', title: 'y', status: 200 }];

    // Act
    const errors = values.map(value => failureOf(() => helper.expectProblem(value as Problem).toBe(notFound)));

    // Assert
    for (const error of errors) {
      error.should.be.instanceOf(ProblemAssertionError);
    }
    errors
      .map(error => error.differences)
      .should.eql([
        ['expected a Problem, received undefined'],
        ['expected a Problem, received {\n  "ok": true,\n  "value": 1\n}'],
        ['expected a Problem, received {\n  "status": 200,\n  "title": "y",\n  "type": "x"\n}'],
      ]);
  });
});
