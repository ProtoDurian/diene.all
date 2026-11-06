import { describe, it } from 'bun:test';
import { ProblemFactory, ProblemGuard, ProblemRegistry, ProblemTransformer } from '@atomicloud/diene.problems';
import 'should';
import { z } from 'zod';
import { portal } from './support/fixtures';

class TransformerFixture {
  readonly fallback = new ProblemRegistry(portal).register({
    id: 'unexpected_error',
    title: 'Unexpected Error',
    status: 500,
    recoverable: false,
    version: 'v1',
    dataSchema: z.object({ source: z.string() }),
  });

  readonly transformer = new ProblemTransformer({
    fallback: this.fallback,
    fallbackData: value => ({ source: typeof value }),
    instance: () => '/operation/42',
  });

  readonly mapped = new ProblemFactory().createProblem(this.fallback, { detail: 'mapped', data: { source: 'remote' } });
}

describe('ProblemGuard', () => {
  it('should recognise only records with the RFC 9457 members and data', () => {
    // Arrange
    const guard = new ProblemGuard();
    const { mapped } = new TransformerFixture();
    const values: readonly unknown[] = [
      mapped,
      null,
      'problem',
      { ...mapped, status: 99 },
      { type: 'x', title: 'y', status: 400 },
      { ...mapped, title: 1 },
      { ...mapped, type: 1 },
    ];

    // Act
    const actual = values.map(value => guard.isProblem(value));

    // Assert
    actual.should.eql([true, false, false, false, false, false, false]);
  });
});

describe('ProblemTransformer.fromError', () => {
  it('should return an existing Problem unchanged', () => {
    // Arrange
    const { mapped, transformer } = new TransformerFixture();
    const expected = mapped;

    // Act
    const actual = transformer.fromError(mapped);

    // Assert
    actual.should.equal(expected);
  });

  it('should unwrap problem, error, and cause members to the innermost value', () => {
    // Arrange
    const { mapped, transformer } = new TransformerFixture();

    // Act
    const viaProblem = transformer.fromError({ problem: mapped });
    const viaCause = transformer.fromError({ cause: { error: new Error('nested failure') } });

    // Assert
    viaProblem.should.equal(mapped);
    viaCause.detail!.should.equal('nested failure');
    viaCause.instance!.should.equal('/operation/42');
    (viaCause.data as object).should.eql({ source: 'object' });
  });

  it('should take the detail from an Error, string, detail, message, or a default', () => {
    // Arrange
    const { fallback, transformer } = new TransformerFixture();
    const inputs: readonly unknown[] = [
      new Error('boom'),
      'plain failure',
      { detail: 'detail failure' },
      { message: 'message failure' },
      42,
    ];

    // Act
    const actual = inputs.map(input => transformer.fromError(input));

    // Assert
    actual
      .map(problem => problem.detail)
      .should.eql(['boom', 'plain failure', 'detail failure', 'message failure', 'An unexpected error occurred']);
    actual.every(problem => problem.type === fallback.type).should.be.true();
  });

  it('should stop at a nested error cycle', () => {
    // Arrange
    const { fallback, transformer } = new TransformerFixture();
    const self: { error?: unknown } = {};
    self.error = self;
    const first: { error?: unknown; message: string } = { message: 'first' };
    const second: { error?: unknown; message: string } = { message: 'second', error: first };
    first.error = second;

    // Act
    const selfCycle = transformer.fromError(self);
    const pairCycle = transformer.fromError(first);

    // Assert
    selfCycle.type.should.equal(fallback.type);
    pairCycle.detail!.should.equal('second');
  });

  it('should omit the instance when no instance mapper is configured', () => {
    // Arrange
    const { fallback } = new TransformerFixture();
    const transformer = new ProblemTransformer({ fallback, fallbackData: () => ({ source: 'none' }) });

    // Act
    const actual = transformer.fromError('failure');

    // Assert
    actual.should.not.have.property('instance');
  });
});

describe('ProblemTransformer.fromHttpError', () => {
  it('should keep direct and nested Problem bodies with the transport status', async () => {
    // Arrange
    const { mapped, transformer } = new TransformerFixture();

    // Act
    const direct = await transformer.fromHttpError(new Response(JSON.stringify(mapped), { status: 503 }));
    const nested = await transformer.fromHttpError(new Response(JSON.stringify({ problem: mapped }), { status: 502 }));

    // Assert
    direct.should.eql({ ...mapped, status: 503 });
    nested.should.eql({ ...mapped, status: 502 });
  });

  it('should map JSON, text, and empty bodies through the fallback', async () => {
    // Arrange
    const { transformer } = new TransformerFixture();
    const located = new Response(JSON.stringify({ message: 'remote message' }), { status: 409 });
    Object.defineProperty(located, 'url', { value: 'https://api.example/notes/42' });

    // Act
    const json = await transformer.fromHttpError(located);
    const text = await transformer.fromHttpError(new Response('plain response', { status: 500 }));
    const empty = await transformer.fromHttpError(new Response(null, { status: 504, statusText: 'Gateway Timeout' }));
    const blank = await transformer.fromHttpError(new Response(null, { status: 500 }));

    // Assert
    json.detail!.should.equal('remote message');
    json.instance!.should.equal('https://api.example/notes/42');
    json.status.should.equal(409);
    text.detail!.should.equal('plain response');
    text.instance!.should.equal('/operation/42');
    empty.detail!.should.equal('Gateway Timeout');
    blank.detail!.should.equal('HTTP request failed');
  });
});
