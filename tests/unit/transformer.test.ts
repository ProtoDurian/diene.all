import { describe, it } from 'bun:test';
import { ProblemFactory, ProblemGuard, ProblemRegistry, ProblemTransformer } from '@atomicloud/diene.problems';
import 'should';
import { z } from 'zod';
import { portal, thrown } from './support/fixtures';

class TransformerFixture {
  readonly registry = new ProblemRegistry(portal);

  readonly fallback = this.registry.register({
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
  it('should recognise records with type, title, and an error status, with or without data', () => {
    // Arrange
    const guard = new ProblemGuard();
    const { mapped } = new TransformerFixture();
    const values: readonly unknown[] = [
      mapped,
      { type: 'x', title: 'y', status: 403 },
      null,
      'problem',
      { ...mapped, status: 99 },
      { ...mapped, status: 200 },
      { ...mapped, title: 1 },
      { ...mapped, type: 1 },
    ];

    // Act
    const actual = values.map(value => guard.isProblem(value));

    // Assert
    actual.should.eql([true, true, false, false, false, false, false, false]);
  });
});

describe('ProblemTransformer.fromError', () => {
  it('should return an equal Problem for an existing Problem', () => {
    // Arrange
    const { mapped, transformer } = new TransformerFixture();

    // Act
    const actual = transformer.fromError(mapped);

    // Assert
    actual.should.eql(mapped);
  });

  it('should rebuild a found Problem without null or unknown members', () => {
    // Arrange
    const { transformer } = new TransformerFixture();
    const found = {
      type: 'https://errors.example/docs/a/b/c/d/v1/unauthorized',
      title: 'Unauthorized',
      status: 403,
      detail: null,
      instance: 7,
      data: null,
      stack: 'secret',
    };

    // Act
    const actual = transformer.fromError({ cause: found });

    // Assert
    actual.should.eql({ type: found.type, title: 'Unauthorized', status: 403 });
  });

  it('should find a Problem through problem, error, and cause members', () => {
    // Arrange
    const { mapped, transformer } = new TransformerFixture();

    // Act
    const viaProblem = transformer.fromError({ problem: mapped });
    const viaError = transformer.fromError({ error: { cause: mapped } });

    // Assert
    viaProblem.should.eql(mapped);
    viaError.should.eql(mapped);
  });

  it('should build the fallback from the original thrown value when no Problem is found', () => {
    // Arrange
    const { fallback } = new TransformerFixture();
    const seen: unknown[] = [];
    const transformer = new ProblemTransformer({
      fallback,
      fallbackData: value => {
        seen.push(value);
        return { source: typeof value };
      },
      instance: value => (value instanceof Error ? `/errors/${value.message}` : undefined),
    });
    const thrownError = new Error('outer', { cause: 42 });

    // Act
    const actual = transformer.fromError(thrownError);

    // Assert
    actual.detail!.should.equal('outer');
    actual.instance!.should.equal('/errors/outer');
    seen.should.eql([thrownError]);
  });

  it('should take the detail from the thrown value, else the first message in the chain, else a default', () => {
    // Arrange
    const { fallback, transformer } = new TransformerFixture();
    const inputs: readonly unknown[] = [
      new Error('boom'),
      'plain failure',
      { detail: 'detail failure' },
      { message: 'message failure' },
      { error: new Error('nested only') },
      { error: 'boom' },
      { cause: { detail: 'deep detail' } },
      42,
    ];

    // Act
    const actual = inputs.map(input => transformer.fromError(input));

    // Assert
    actual
      .map(problem => problem.detail)
      .should.eql([
        'boom',
        'plain failure',
        'detail failure',
        'message failure',
        'nested only',
        'boom',
        'deep detail',
        'An unexpected error occurred',
      ]);
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
    pairCycle.detail!.should.equal('first');
  });

  it('should mint a data-less fallback without data or instance mappers', () => {
    // Arrange
    const { registry } = new TransformerFixture();
    const fallback = registry.register({
      id: 'upstream_failed',
      title: 'Upstream Failed',
      status: 502,
      recoverable: true,
      version: 'v1',
    });
    const transformer = new ProblemTransformer({ fallback });

    // Act
    const actual = transformer.fromError('failure');

    // Assert
    actual.should.eql({ type: fallback.type, title: 'Upstream Failed', status: 502, detail: 'failure' });
  });
});

describe('ProblemTransformer.fromHttpError', () => {
  it('should keep direct and nested Problem bodies with the transport error status', async () => {
    // Arrange
    const { mapped, transformer } = new TransformerFixture();

    // Act
    const direct = await transformer.fromHttpError(new Response(JSON.stringify(mapped), { status: 503 }));
    const nested = await transformer.fromHttpError(new Response(JSON.stringify({ problem: mapped }), { status: 502 }));

    // Assert
    direct.should.eql({ ...mapped, status: 503 });
    nested.should.eql({ ...mapped, status: 502 });
  });

  it('should keep a data-less RFC 9457 body instead of replacing it with the fallback', async () => {
    // Arrange
    const { transformer } = new TransformerFixture();
    const body = { type: 'https://errors.example/docs/a/b/c/d/v1/unauthorized', title: 'Unauthorized', status: 403 };

    // Act
    const actual = await transformer.fromHttpError(
      new Response(JSON.stringify({ ...body, detail: 'no access', extra: 'leak' }), { status: 403 }),
    );

    // Assert
    actual.should.eql({ ...body, detail: 'no access' });
  });

  it('should keep the body or entry status when the transport status is not an error status', async () => {
    // Arrange
    const { fallback, mapped, transformer } = new TransformerFixture();

    // Act
    const found = await transformer.fromHttpError(new Response(JSON.stringify(mapped), { status: 200 }));
    const minted = await transformer.fromHttpError(new Response('redirected', { status: 302 }));

    // Assert
    found.status.should.equal(500);
    minted.status.should.equal(fallback.status);
  });

  it('should map JSON, text, and empty bodies through the fallback with the configured instance only', async () => {
    // Arrange
    const { transformer } = new TransformerFixture();
    const located = new Response(JSON.stringify({ message: 'remote message' }), { status: 409 });
    Object.defineProperty(located, 'url', { value: 'https://api.internal/notes/42?token=secret' });

    // Act
    const json = await transformer.fromHttpError(located);
    const text = await transformer.fromHttpError(new Response('plain response', { status: 500 }));
    const empty = await transformer.fromHttpError(new Response(null, { status: 504, statusText: 'Gateway Timeout' }));
    const blank = await transformer.fromHttpError(new Response(null, { status: 500 }));

    // Assert
    json.detail!.should.equal('remote message');
    json.instance!.should.equal('/operation/42');
    json.status.should.equal(409);
    text.detail!.should.equal('plain response');
    empty.detail!.should.equal('Gateway Timeout');
    blank.detail!.should.equal('HTTP request failed');
  });
});

describe('ProblemTransformer construction', () => {
  it('should require fallbackData for a fallback with a data schema', () => {
    // Arrange
    const { fallback } = new TransformerFixture();
    const options = { fallback };

    // Act
    // @ts-expect-error a fallback with a data schema needs a fallbackData mapper
    const error = thrown(() => new ProblemTransformer(options));

    // Assert
    error.should.be.instanceOf(TypeError);
    error.message.should.equal('Problem transformer fallback unexpected_error needs a fallbackData mapper');
  });

  it('should refuse fallbackData for a fallback without a data schema', () => {
    // Arrange
    const { registry } = new TransformerFixture();
    const fallback = registry.register({ id: 'gone', title: 'Gone', status: 410, recoverable: false, version: 'v1' });
    const options = { fallback, fallbackData: () => ({}) };

    // Act
    // @ts-expect-error a fallback without a data schema takes no fallbackData mapper
    const error = thrown(() => new ProblemTransformer(options));

    // Assert
    error.message.should.equal('Problem transformer fallback gone must not take a fallbackData mapper');
  });
});

describe('ProblemTransformer.fromHttpError messages', () => {
  it('should take the first message nested in an HTTP body, else the generic detail', async () => {
    // Arrange
    const { transformer } = new TransformerFixture();

    // Act
    const nested = await transformer.fromHttpError(
      new Response(JSON.stringify({ error: { message: 'quota exceeded' } }), { status: 429 }),
    );
    const silent = await transformer.fromHttpError(new Response(JSON.stringify({ code: 7 }), { status: 500 }));

    // Assert
    nested.detail!.should.equal('quota exceeded');
    nested.status.should.equal(429);
    silent.detail!.should.equal('An unexpected error occurred');
  });
});
