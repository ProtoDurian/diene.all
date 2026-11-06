import { describe, it } from 'bun:test';
import 'should';
import { z } from 'zod';
import { EnvOverrides, NESTING_SEPARATOR } from '../../src/lib/env.js';
import { ConfigLoaderError } from '../../src/lib/errors.js';
import type { ConfigRecord } from '../../src/lib/merge.js';

const PREFIX = 'ATOMI_';
const overrides = new EnvOverrides();

describe('NESTING_SEPARATOR', () => {
  it('should be the double underscore', () => {
    // Arrange
    const expected = '__';

    // Act
    const actual = NESTING_SEPARATOR;

    // Assert
    actual.should.equal(expected);
  });
});

describe('EnvOverrides.apply — name matching', () => {
  it.each([
    { style: 'snake', key: 'max_retries' },
    { style: 'pascal', key: 'MaxRetries' },
    { style: 'camel', key: 'maxRetries' },
    { style: 'kebab', key: 'max-retries' },
  ])('should match a snake env segment onto a $style key', ({ key }) => {
    // Arrange
    const base: ConfigRecord = { server: { [key]: 1 } };

    // Act
    const actual = overrides.apply(base, { ATOMI_SERVER__MAX_RETRIES: '9' }, PREFIX);

    // Assert
    actual.should.deepEqual({ server: { [key]: 9 } });
  });

  it.each([
    'ATOMI_SERVER__MAX_RETRIES',
    'ATOMI_SERVER__MAXRETRIES',
    'ATOMI_server__max_retries',
    'ATOMI_Server__Max-Retries',
  ])('should match %s onto the existing camelCase key', envKey => {
    // Arrange
    const base: ConfigRecord = { server: { maxRetries: 1 } };

    // Act
    const actual = overrides.apply(base, { [envKey]: '9' }, PREFIX);

    // Assert
    actual.should.deepEqual({ server: { maxRetries: 9 } });
  });

  it('should lowercase a segment that matches no existing key', () => {
    // Arrange
    const base: ConfigRecord = {};

    // Act
    const actual = overrides.apply(base, { ATOMI_SERVER__HOST: 'h' }, PREFIX);

    // Assert
    actual.should.deepEqual({ server: { host: 'h' } });
  });
});

describe('EnvOverrides.apply — coercion and unset', () => {
  it('should coerce booleans and numbers', () => {
    // Arrange
    const base: ConfigRecord = { server: { port: 80, debug: false } };

    // Act
    const actual = overrides.apply(base, { ATOMI_SERVER__PORT: '8080', ATOMI_SERVER__DEBUG: 'true' }, PREFIX);

    // Assert
    actual.should.deepEqual({ server: { port: 8080, debug: true } });
  });

  it.each([
    { label: 'a blank value', env: { ATOMI_SERVER__HOST: '' } },
    { label: 'an undefined value', env: { ATOMI_SERVER__HOST: undefined } },
    { label: 'an unprefixed key', env: { OTHER__SERVER__HOST: 'x' } },
    { label: 'a trailing separator', env: { ATOMI_SERVER__: 'x' } },
    { label: 'an empty middle segment', env: { ATOMI_SERVER____HOST: 'x' } },
    { label: 'a bare prefix', env: { ATOMI_: 'x' } },
  ])('should leave the target unchanged for $label', ({ env }) => {
    // Arrange
    const base: ConfigRecord = { server: { host: 'keep' } };

    // Act
    const actual = overrides.apply(base, env, PREFIX);

    // Assert
    actual.should.deepEqual({ server: { host: 'keep' } });
  });
});

describe('EnvOverrides.apply — nesting and indexed lists', () => {
  it.each([
    { label: 'a new nested object', base: {}, env: { ATOMI_A__B__C: '1' }, expected: { a: { b: { c: 1 } } } },
    {
      label: 'an existing array by index',
      base: { endpoints: ['zero', 'one'] },
      env: { ATOMI_ENDPOINTS__0: 'primary', ATOMI_ENDPOINTS__2: 'third' },
      expected: { endpoints: ['primary', 'one', 'third'] },
    },
    {
      label: 'a fresh array',
      base: {},
      env: { ATOMI_LIST__0: 'a', ATOMI_LIST__1: 'b' },
      expected: { list: ['a', 'b'] },
    },
    {
      label: 'an object inside a fresh array',
      base: {},
      env: { ATOMI_ITEMS__0__NAME: 'first' },
      expected: { items: [{ name: 'first' }] },
    },
    {
      label: 'an object inside an existing array',
      base: { items: [{ name: 'a', port: 1 }] },
      env: { ATOMI_ITEMS__0__PORT: '2' },
      expected: { items: [{ name: 'a', port: 2 }] },
    },
    { label: 'a scalar replaced by an object', base: { a: 1 }, env: { ATOMI_A__B: 'x' }, expected: { a: { b: 'x' } } },
  ])('should handle $label', ({ base, env, expected }) => {
    // Arrange
    const target: ConfigRecord = base;

    // Act
    const actual = overrides.apply(target, env, PREFIX);

    // Assert
    actual.should.deepEqual(expected);
  });

  it('should not mutate the input object', () => {
    // Arrange
    const base: ConfigRecord = { server: { port: 80 } };

    // Act
    overrides.apply(base, { ATOMI_SERVER__PORT: '9090' }, PREFIX);

    // Assert
    base.should.deepEqual({ server: { port: 80 } });
  });
});

describe('EnvOverrides.apply — schema-directed coercion', () => {
  const schema = z.object({
    db: z.object({ password: z.string(), id: z.string(), zip: z.string(), token: z.string() }),
    svc: z.object({
      maxRetries: z.number().optional(),
      debug: z.boolean().default(false),
      name: z.string().nullable(),
    }),
    tags: z.array(z.string()).optional(),
    items: z.array(z.object({ maxRetries: z.number() })).optional(),
    piped: z.string().transform(value => value.length),
  });

  it.each([
    {
      label: 'an all-digit secret into a string',
      env: { ATOMI_DB__PASSWORD: '123456' },
      path: ['db', 'password'],
      expected: '123456',
    },
    {
      label: 'an id past 2^53 into a string',
      env: { ATOMI_DB__ID: '9007199254740993' },
      path: ['db', 'id'],
      expected: '9007199254740993',
    },
    {
      label: 'a leading-zero code into a string',
      env: { ATOMI_DB__ZIP: '0123' },
      path: ['db', 'zip'],
      expected: '0123',
    },
    {
      label: 'a boolean-looking token into a string',
      env: { ATOMI_DB__TOKEN: 'true' },
      path: ['db', 'token'],
      expected: 'true',
    },
    {
      label: 'a camelCase optional number absent from yaml',
      env: { ATOMI_SVC__MAX_RETRIES: '3' },
      path: ['svc', 'maxRetries'],
      expected: 3,
    },
    { label: 'a defaulted boolean', env: { ATOMI_SVC__DEBUG: 'TRUE' }, path: ['svc', 'debug'], expected: true },
    {
      label: 'a non-numeric word into a number',
      env: { ATOMI_SVC__MAX_RETRIES: '1e3' },
      path: ['svc', 'maxRetries'],
      expected: '1e3',
    },
    {
      label: 'a number-looking value into a nullable string',
      env: { ATOMI_SVC__NAME: '42' },
      path: ['svc', 'name'],
      expected: '42',
    },
    {
      label: 'a number-looking value into an indexed string list',
      env: { ATOMI_TAGS__0: '7' },
      path: ['tags', '0'],
      expected: '7',
    },
    {
      label: 'an indexed list of camelCase objects',
      env: { ATOMI_ITEMS__0__MAX_RETRIES: '2' },
      path: ['items', '0', 'maxRetries'],
      expected: 2,
    },
    { label: 'the input side of a pipe', env: { ATOMI_PIPED: '99' }, path: ['piped'], expected: '99' },
    {
      label: 'a key the schema does not know',
      env: { ATOMI_EXTRA__COUNT: '5' },
      path: ['extra', 'count'],
      expected: 5,
    },
  ])('should place $label', ({ env, path, expected }) => {
    // Arrange
    const base: ConfigRecord = { db: { password: '', id: '', zip: '', token: '' }, svc: {} };

    // Act
    const actual = overrides.apply(base, env, PREFIX, schema);

    // Assert
    const leaf = path.reduce<unknown>((node, key) => (node as Record<string, unknown>)[key], actual);
    (leaf as object).should.equal(expected);
  });
});

describe('EnvOverrides.apply — refusals and ordering', () => {
  it.each([
    {
      label: 'an index past the bound',
      base: { list: [] },
      env: { ATOMI_LIST__5000: 'x' },
      message: /ATOMI_LIST__5000/,
    },
    {
      label: 'a non-numeric segment into an array',
      base: { list: ['a'] },
      env: { ATOMI_LIST__FOO: 'x' },
      message: /ATOMI_LIST__FOO/,
    },
    {
      label: 'an ambiguous key match',
      base: { myKey: 1, my_key: 2 },
      env: { ATOMI_MY_KEY: '3' },
      message: /ATOMI_MY_KEY.*myKey.*my_key/,
    },
  ])('should throw ConfigLoaderError for $label', ({ base, env, message }) => {
    // Arrange
    const target: ConfigRecord = base;

    // Act
    const act = () => overrides.apply(target, env, PREFIX);

    // Assert
    act.should.throw(ConfigLoaderError, { message });
  });

  it.each([
    { label: 'parent first', env: { ATOMI_A: 'v', ATOMI_A__B: 'w' } },
    { label: 'child first', env: { ATOMI_A__B: 'w', ATOMI_A: 'v' } },
  ])('should apply shorter paths first whatever the env order ($label)', ({ env }) => {
    // Arrange
    const base: ConfigRecord = {};

    // Act
    const actual = overrides.apply(base, env, PREFIX);

    // Assert
    actual.should.deepEqual({ a: { b: 'w' } });
  });
});

describe('EnvOverrides.keysFor', () => {
  it('should name every non-blank variable that targets a path', () => {
    // Arrange
    const env = {
      ATOMI_APP__LANDSCAPE: 'prod',
      ATOMI_app__landscape: '',
      ATOMI_APP__NAME: 'x',
      OTHER_APP__LANDSCAPE: 'y',
    };

    // Act
    const actual = overrides.keysFor(env, PREFIX, ['app', 'landscape']);

    // Assert
    actual.should.deepEqual(['ATOMI_APP__LANDSCAPE']);
  });
});

describe('EnvOverrides.apply — exact bigint through the loader schema', () => {
  it('should hand z.coerce.bigint the raw text so 2^53 + 1 survives', () => {
    // Arrange
    const schema = z.object({ ids: z.object({ big: z.coerce.bigint() }) });

    // Act
    const actual = schema.parse(overrides.apply({}, { ATOMI_IDS__BIG: '9007199254740993' }, PREFIX, schema));

    // Assert
    actual.ids.big.toString().should.equal('9007199254740993');
  });
});

enum Level {
  Debug = 0,
  Info = 1,
}

describe('EnvOverrides.apply — through unions, intersections, records, tuples and catchall', () => {
  const schema = z.object({
    svc: z.object({
      auth: z.discriminatedUnion('kind', [
        z.object({ kind: z.literal('a'), maxRetries: z.number().optional(), token: z.string() }),
        z.object({ kind: z.literal('b'), token: z.string() }),
      ]),
      joined: z.object({ host: z.string() }).and(z.object({ maxRetries: z.number().optional() })),
      tenants: z.record(z.string(), z.object({ maxRetries: z.number().optional(), name: z.string() })),
      labels: z.record(z.string(), z.string()),
      pair: z.tuple([z.string(), z.number()]),
      extra: z.object({}).catchall(z.string()),
      level: z.enum(Level).optional(),
      on: z.coerce.boolean().optional(),
    }),
  });
  const base: ConfigRecord = {
    svc: {
      auth: { kind: 'a', token: 'x' },
      joined: { host: 'h' },
      tenants: { t1: { name: 'n' } },
      labels: {},
      pair: ['a', 1],
      extra: {},
    },
  };

  it.each([
    {
      label: 'an absent key in a discriminated union',
      name: 'ATOMI_SVC__AUTH__MAX_RETRIES',
      raw: '3',
      path: ['auth', 'maxRetries'],
      expected: 3,
    },
    {
      label: 'an absent key in an intersection',
      name: 'ATOMI_SVC__JOINED__MAX_RETRIES',
      raw: '3',
      path: ['joined', 'maxRetries'],
      expected: 3,
    },
    {
      label: 'an absent key in a record of objects',
      name: 'ATOMI_SVC__TENANTS__T1__MAX_RETRIES',
      raw: '3',
      path: ['tenants', 't1', 'maxRetries'],
      expected: 3,
    },
    {
      label: 'a union string leaf',
      name: 'ATOMI_SVC__AUTH__TOKEN',
      raw: '123456',
      path: ['auth', 'token'],
      expected: '123456',
    },
    {
      label: 'an intersection string leaf',
      name: 'ATOMI_SVC__JOINED__HOST',
      raw: '0123',
      path: ['joined', 'host'],
      expected: '0123',
    },
    {
      label: 'a record string value',
      name: 'ATOMI_SVC__LABELS__TEAM',
      raw: '123',
      path: ['labels', 'team'],
      expected: '123',
    },
    { label: 'a tuple string item', name: 'ATOMI_SVC__PAIR__0', raw: '0123', path: ['pair', '0'], expected: '0123' },
    { label: 'a tuple number item', name: 'ATOMI_SVC__PAIR__1', raw: '7', path: ['pair', '1'], expected: 7 },
    {
      label: 'a catchall string value',
      name: 'ATOMI_SVC__EXTRA__CODE',
      raw: '0123',
      path: ['extra', 'code'],
      expected: '0123',
    },
    { label: 'a numeric TS enum', name: 'ATOMI_SVC__LEVEL', raw: '1', path: ['level'], expected: 1 },
    { label: 'false into a coerce boolean', name: 'ATOMI_SVC__ON', raw: 'false', path: ['on'], expected: false },
  ])('should reach $label', ({ name, raw, path, expected }) => {
    // Arrange
    const env = { [name]: raw };

    // Act
    const actual = schema.parse(overrides.apply(base, env, PREFIX, schema));

    // Assert
    const leaf = path.reduce<unknown>((node, key) => (node as Record<string, unknown>)[key], actual.svc);
    (leaf as object).should.equal(expected);
  });

  it.each(['0', 'no'])('should refuse "%s" for a boolean instead of letting z.coerce.boolean read it as true', raw => {
    // Arrange
    const env = { ATOMI_SVC__ON: raw };

    // Act
    const act = () => overrides.apply(base, env, PREFIX, schema);

    // Assert
    act.should.throw(ConfigLoaderError, { message: /ATOMI_SVC__ON: expected true or false/ });
  });
});

describe('EnvOverrides.apply — nodes the schema cannot see into', () => {
  const schema = z.object({ blob: z.custom<object>(() => true), meta: z.unknown() });

  it('should throw rather than drop a key under a schema it cannot walk', () => {
    // Arrange
    const env = { ATOMI_BLOB__MAX_RETRIES: '3' };

    // Act
    const act = () => overrides.apply({}, env, PREFIX, schema);

    // Assert
    act.should.throw(ConfigLoaderError, { message: /ATOMI_BLOB__MAX_RETRIES/ });
  });

  it('should keep the plain rule under z.unknown()', () => {
    // Arrange
    const env = { ATOMI_META__MAX_RETRIES: '3' };

    // Act
    const actual = overrides.apply({}, env, PREFIX, schema);

    // Assert
    actual.should.deepEqual({ meta: { max_retries: 3 } });
  });
});

describe('EnvOverrides.apply — plain booleans', () => {
  it('should refuse a non-boolean word for z.boolean()', () => {
    // Arrange
    const schema = z.object({ svc: z.object({ debug: z.boolean() }) });

    // Act
    const act = () => overrides.apply({}, { ATOMI_SVC__DEBUG: 'yes' }, PREFIX, schema);

    // Assert
    act.should.throw(ConfigLoaderError, { message: 'ATOMI_SVC__DEBUG: expected true or false, got "yes"' });
  });
});

describe('EnvOverrides.apply — keys deeper under a schema it cannot walk', () => {
  it.each([
    {
      label: 'two levels under z.custom',
      schema: z.object({ blob: z.custom<{ inner: { maxRetries?: number } }>(() => true) }),
      base: { blob: { inner: {} } },
      name: 'ATOMI_BLOB__INNER__MAX_RETRIES',
    },
    {
      label: 'two levels under a custom member of a union',
      schema: z.object({ cfg: z.union([z.custom<{ inner: object }>(() => true), z.string()]) }),
      base: { cfg: { inner: {} } },
      name: 'ATOMI_CFG__INNER__MAX_RETRIES',
    },
  ])('should throw for a key $label', ({ schema, base, name }) => {
    // Arrange
    const env = { [name]: '3' };

    // Act
    const act = () => overrides.apply(base, env, PREFIX, schema);

    // Assert
    act.should.throw(ConfigLoaderError, { message: new RegExp(name) });
  });
});

describe('EnvOverrides.apply — preprocess, null members and catch', () => {
  it.each([
    {
      label: 'an absent key two levels under z.preprocess',
      schema: z.object({
        cfg: z.preprocess(v => v, z.object({ inner: z.object({ maxRetries: z.number().optional() }) })),
      }),
      base: { cfg: { inner: {} } },
      name: 'ATOMI_CFG__INNER__MAX_RETRIES',
      raw: '3',
      path: ['cfg', 'inner', 'maxRetries'],
      expected: 3,
    },
    {
      label: 'an absent key under z.preprocess',
      schema: z.object({
        cfg: z.preprocess(v => v, z.object({ maxRetries: z.number().optional(), name: z.string() })),
      }),
      base: { cfg: { name: 'n' } },
      name: 'ATOMI_CFG__MAX_RETRIES',
      raw: '3',
      path: ['cfg', 'maxRetries'],
      expected: 3,
    },
    {
      label: 'a z.preprocess string leaf',
      schema: z.object({ code: z.preprocess(v => v, z.string()) }),
      base: {},
      name: 'ATOMI_CODE',
      raw: '0123',
      path: ['code'],
      expected: '0123',
    },
    {
      label: 'a string or null leaf',
      schema: z.object({ code: z.union([z.string(), z.null()]) }),
      base: { code: null },
      name: 'ATOMI_CODE',
      raw: '0123',
      path: ['code'],
      expected: '0123',
    },
    {
      label: 'a string or undefined leaf',
      schema: z.object({ code: z.string().or(z.undefined()) }),
      base: {},
      name: 'ATOMI_CODE',
      raw: '0123',
      path: ['code'],
      expected: '0123',
    },
    {
      label: 'the .catch() fallback for a non-boolean word',
      schema: z.object({ m: z.boolean().catch(false) }),
      base: {},
      name: 'ATOMI_M',
      raw: 'yes',
      path: ['m'],
      expected: false,
    },
  ])('should reach $label', ({ schema, base, name, raw, path, expected }) => {
    // Arrange
    const env = { [name]: raw };

    // Act
    const actual = schema.parse(overrides.apply(base, env, PREFIX, schema));

    // Assert
    const leaf = path.reduce<unknown>((node, key) => (node as Record<string, unknown>)[key], actual);
    (leaf as object).should.equal(expected);
  });
});
