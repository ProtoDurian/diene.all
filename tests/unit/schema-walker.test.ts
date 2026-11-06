import { describe, it } from 'bun:test';
import 'should';
import { z } from 'zod';
import { SchemaWalker } from '../../src/lib/schema-walker.js';

const walker = new SchemaWalker();

describe('SchemaWalker.kind', () => {
  it.each([
    { label: 'a string', schema: z.string(), expected: 'string' },
    { label: 'an enum', schema: z.enum(['a', 'b']), expected: 'string' },
    { label: 'a coerced number', schema: z.coerce.number(), expected: 'number' },
    { label: 'a boolean', schema: z.boolean(), expected: 'boolean' },
    { label: 'an array', schema: z.array(z.string()), expected: 'array' },
    { label: 'an object', schema: z.object({}), expected: 'object' },
    { label: 'a string literal', schema: z.literal('a'), expected: 'string' },
    { label: 'a number literal', schema: z.literal(1), expected: 'number' },
    { label: 'a mixed literal', schema: z.literal(['a', 1]), expected: 'unknown' },
    { label: 'a bigint literal', schema: z.literal(1n), expected: 'string' },
    { label: 'an undefined literal', schema: z.literal(undefined), expected: 'unknown' },
    { label: 'a union', schema: z.union([z.string(), z.number()]), expected: 'unknown' },
    { label: 'no schema', schema: undefined, expected: 'unknown' },
    {
      label: 'an optional nullable default string',
      schema: z.string().nullable().optional().default('x'),
      expected: 'string',
    },
    {
      label: 'a readonly catch prefault number',
      schema: z.number().catch(1).prefault(2).readonly(),
      expected: 'number',
    },
    { label: 'a required optional boolean', schema: z.boolean().optional().nonoptional(), expected: 'boolean' },
    { label: 'the input side of a pipe', schema: z.string().pipe(z.coerce.number()), expected: 'string' },
    { label: 'a lazy string', schema: z.lazy(() => z.string()), expected: 'string' },
    { label: 'a coerced bigint, kept as text for an exact parse', schema: z.coerce.bigint(), expected: 'string' },
    { label: 'a coerced date, kept as text', schema: z.coerce.date(), expected: 'string' },
  ])('should classify $label', ({ schema, expected }) => {
    // Arrange
    const target = schema;

    // Act
    const actual = walker.kind(target);

    // Assert
    actual.should.equal(expected);
  });
});

describe('SchemaWalker.keys and child', () => {
  const schema = z.object({ svc: z.object({ maxRetries: z.number() }).optional(), tags: z.array(z.string()) });

  it.each([
    { label: 'an object', target: schema, expected: ['svc', 'tags'] },
    { label: 'a wrapped object', target: schema.shape.svc, expected: ['maxRetries'] },
    { label: 'a non-object', target: z.string(), expected: [] },
    { label: 'no schema', target: undefined, expected: [] },
  ])('should list the keys of $label', ({ target, expected }) => {
    // Arrange
    const node = target;

    // Act
    const actual = walker.keys(node);

    // Assert
    actual.should.deepEqual(expected);
  });

  it.each([
    { label: 'an object key', key: 'svc', expected: 'object' },
    { label: 'an unknown key', key: 'missing', expected: 'unknown' },
    { label: 'an array element', key: 'tags', index: 0, expected: 'string' },
  ])('should find the child for $label', ({ key, index, expected }) => {
    // Arrange
    const parent = index === undefined ? schema : walker.child(schema, key);

    // Act
    const actual = walker.kind(walker.child(parent, index ?? key));

    // Assert
    actual.should.equal(expected);
  });

  it('should find no child under a numeric key of an object', () => {
    // Arrange
    const parent = schema;

    // Act
    const actual = walker.child(parent, 0);

    // Assert
    (actual === undefined).should.be.true();
  });
});
