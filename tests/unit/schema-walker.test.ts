import { describe, it } from 'bun:test';
import 'should';
import { z } from 'zod';
import { SchemaWalker } from '../../src/lib/schema-walker.js';

const walker = new SchemaWalker();

enum Level {
  Debug = 0,
  Info = 1,
}

describe('SchemaWalker.kind', () => {
  it.each([
    { label: 'a string', schema: z.string(), expected: 'string' },
    { label: 'a string enum', schema: z.enum(['a', 'b']), expected: 'string' },
    { label: 'a numeric TS enum', schema: z.enum(Level), expected: 'number' },
    { label: 'a mixed enum', schema: z.enum({ a: 'a', b: 1 }), expected: 'unknown' },
    { label: 'a coerced number', schema: z.coerce.number(), expected: 'number' },
    { label: 'a boolean', schema: z.boolean(), expected: 'boolean' },
    { label: 'a coerced boolean', schema: z.coerce.boolean(), expected: 'boolean' },
    { label: 'an array', schema: z.array(z.string()), expected: 'array' },
    { label: 'a tuple', schema: z.tuple([z.string()]), expected: 'array' },
    { label: 'an object', schema: z.object({}), expected: 'object' },
    { label: 'a record', schema: z.record(z.string(), z.string()), expected: 'object' },
    { label: 'a string literal', schema: z.literal('a'), expected: 'string' },
    { label: 'a number literal', schema: z.literal(1), expected: 'number' },
    { label: 'a mixed literal', schema: z.literal(['a', 1]), expected: 'unknown' },
    { label: 'a bigint literal', schema: z.literal(1n), expected: 'string' },
    { label: 'an undefined literal', schema: z.literal(undefined), expected: 'unknown' },
    { label: 'a coerced bigint', schema: z.coerce.bigint(), expected: 'string' },
    { label: 'a coerced date', schema: z.coerce.date(), expected: 'string' },
    { label: 'a union of strings', schema: z.union([z.string(), z.enum(['a'])]), expected: 'string' },
    { label: 'a union of string and number', schema: z.union([z.string(), z.number()]), expected: 'unknown' },
    { label: 'an intersection of objects', schema: z.object({}).and(z.object({})), expected: 'object' },
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
    { label: 'the output side of a preprocess', schema: z.preprocess(v => v, z.string()), expected: 'string' },
    { label: 'the input side of a transform', schema: z.string().transform(Number), expected: 'string' },
    { label: 'a union of string and null', schema: z.union([z.string(), z.null()]), expected: 'string' },
    { label: 'a string or undefined', schema: z.string().or(z.undefined()), expected: 'string' },
    { label: 'only null', schema: z.null(), expected: 'unknown' },
    { label: 'a string or null literal', schema: z.string().or(z.literal(null)), expected: 'string' },
    { label: 'a string or undefined literal', schema: z.string().or(z.literal(undefined)), expected: 'string' },
    { label: 'a literal list holding null', schema: z.literal(['auto', null]).or(z.string()), expected: 'string' },
    { label: 'a lazy string', schema: z.lazy(() => z.string()), expected: 'string' },
    { label: 'no schema', schema: undefined, expected: 'unknown' },
  ])('should classify $label', ({ schema, expected }) => {
    // Arrange
    const node = walker.root(schema);

    // Act
    const actual = walker.kind(node);

    // Assert
    actual.should.equal(expected);
  });
});

describe('SchemaWalker.keys and child', () => {
  const schema = z.object({
    svc: z.object({ maxRetries: z.number() }).optional(),
    tags: z.array(z.string()),
    auth: z.union([z.object({ token: z.string() }), z.object({ user: z.string() })]),
    joined: z.object({ host: z.string() }).and(z.object({ port: z.number() })),
    labels: z.record(z.string(), z.number()),
    pair: z.tuple([z.string()], z.boolean()),
    extra: z.object({ id: z.string() }).catchall(z.number()),
    strict: z.strictObject({ id: z.string() }),
  });
  const root = walker.root(schema);

  it.each([
    { label: 'an object', path: [], expected: ['svc', 'tags', 'auth', 'joined', 'labels', 'pair', 'extra', 'strict'] },
    { label: 'a wrapped object', path: ['svc'], expected: ['maxRetries'] },
    { label: 'a union of objects', path: ['auth'], expected: ['token', 'user'] },
    { label: 'an intersection', path: ['joined'], expected: ['host', 'port'] },
    { label: 'a record', path: ['labels'], expected: [] },
    { label: 'a leaf', path: ['tags', 0], expected: [] },
  ])('should list the keys of $label', ({ path, expected }) => {
    // Arrange
    const node = path.reduce((current, key) => walker.child(current, key), root);

    // Act
    const actual = walker.keys(node);

    // Assert
    actual.should.deepEqual(expected);
  });

  it.each([
    { label: 'an object key', path: ['svc'], expected: 'object' },
    { label: 'an unknown key', path: ['missing'], expected: 'unknown' },
    { label: 'a numeric key of an object', path: [0], expected: 'unknown' },
    { label: 'an array element', path: ['tags', 0], expected: 'string' },
    { label: 'a union member key', path: ['auth', 'user'], expected: 'string' },
    { label: 'an intersection member key', path: ['joined', 'port'], expected: 'number' },
    { label: 'a record value', path: ['labels', 'any'], expected: 'number' },
    { label: 'a numeric key of a record', path: ['labels', 0], expected: 'number' },
    { label: 'a tuple item', path: ['pair', 0], expected: 'string' },
    { label: 'a tuple rest item', path: ['pair', 3], expected: 'boolean' },
    { label: 'a tuple by name', path: ['pair', 'x'], expected: 'unknown' },
    { label: 'a catchall shape key', path: ['extra', 'id'], expected: 'string' },
    { label: 'a catchall value', path: ['extra', 'other'], expected: 'number' },
    { label: 'an unknown key of a strict object', path: ['strict', 'other'], expected: 'unknown' },
  ])('should find the child for $label', ({ path, expected }) => {
    // Arrange
    const node = path.reduce((current, key) => walker.child(current, key), root);

    // Act
    const actual = walker.kind(node);

    // Assert
    actual.should.equal(expected);
  });
});

describe('SchemaWalker.opaque', () => {
  it.each([
    { label: 'a custom schema', schema: z.custom<object>(() => true), expected: true },
    { label: 'a map', schema: z.map(z.string(), z.string()), expected: true },
    {
      label: 'a union holding a custom schema',
      schema: z.union([z.object({}), z.custom<object>(() => true)]),
      expected: true,
    },
    { label: 'an object', schema: z.object({}), expected: false },
    { label: 'z.unknown()', schema: z.unknown(), expected: false },
    { label: 'no schema', schema: undefined, expected: false },
  ])('should report $expected for $label', ({ schema, expected }) => {
    // Arrange
    const node = walker.root(schema);

    // Act
    const actual = walker.opaque(node);

    // Assert
    actual.should.equal(expected);
  });
});

describe('SchemaWalker.caught', () => {
  it.each([
    { label: 'a catch boolean', schema: z.boolean().catch(false), expected: true },
    { label: 'an optional catch boolean', schema: z.boolean().catch(false).optional(), expected: true },
    { label: 'a lazy catch boolean', schema: z.lazy(() => z.boolean().catch(false)), expected: true },
    { label: 'a catch boolean or null', schema: z.union([z.boolean().catch(false), z.null()]), expected: true },
    { label: 'a preprocessed catch boolean', schema: z.preprocess(v => v, z.boolean().catch(false)), expected: true },
    {
      label: 'a transformed catch boolean',
      schema: z
        .boolean()
        .catch(false)
        .transform(v => v),
      expected: true,
    },
    {
      label: 'a union with an uncaught boolean',
      schema: z.union([z.boolean().catch(false), z.boolean()]),
      expected: false,
    },
    { label: 'a plain boolean', schema: z.boolean(), expected: false },
    { label: 'an optional boolean', schema: z.boolean().optional(), expected: false },
    { label: 'no schema', schema: undefined, expected: false },
  ])('should report $expected for $label', ({ schema, expected }) => {
    // Arrange
    const node = walker.root(schema);

    // Act
    const actual = walker.caught(node);

    // Assert
    actual.should.equal(expected);
  });
});
