import { describe, it } from 'bun:test';
import { readFile } from 'node:fs/promises';
import { resolve } from 'node:path';
import Ajv2020 from 'ajv/dist/2020';
import 'should';
import { parse } from 'yaml';
import { z } from 'zod';
import { ConfigRegistry } from '../../src/lib/registry.js';
import { JsonSchemaGenerator } from '../../src/lib/schema.js';

const registry = ConfigRegistry.create()
  .register('server', z.object({ port: z.coerce.number(), host: z.string(), tags: z.array(z.string()).optional() }))
  .register('client', z.object({ name: z.string() }));

const SNAPSHOT = {
  $schema: 'https://json-schema.org/draft/2020-12/schema',
  type: 'object',
  properties: {
    server: {
      type: 'object',
      properties: {
        port: { type: 'number' },
        host: { type: 'string' },
        tags: { type: 'array', items: { type: 'string' } },
      },
      required: ['port', 'host'],
      additionalProperties: false,
    },
    client: {
      type: 'object',
      properties: { name: { type: 'string' } },
      required: ['name'],
      additionalProperties: false,
    },
  },
  required: ['server', 'client'],
  additionalProperties: false,
};

const generator = new JsonSchemaGenerator();

describe('JsonSchemaGenerator.generate', () => {
  it.each([
    { label: 'the registry snapshot', options: undefined, expected: SNAPSHOT },
    {
      label: 'the snapshot with a stamped $id',
      options: { id: 'https://atomi/config.json' },
      expected: { $id: 'https://atomi/config.json', ...SNAPSHOT },
    },
  ])('should emit $label', ({ options, expected }) => {
    // Arrange
    const source = registry;

    // Act
    const actual = generator.generate(source, options);

    // Assert
    actual.should.deepEqual(expected);
  });
});

describe('JsonSchemaGenerator.generate — editor validation of a sample YAML', () => {
  const ajv = new Ajv2020({ allErrors: true, strict: true });
  const fixtures = resolve(import.meta.dir, '../fixtures/schema');

  it.each([
    { file: 'config.yaml', valid: true, errors: [] },
    { file: 'invalid.config.yaml', valid: false, errors: ['/server/port must be number'] },
  ])('should judge $file with the generated draft 2020-12 schema', async ({ file, valid, errors }) => {
    // Arrange
    const text = await readFile(resolve(fixtures, file), 'utf8');
    const validate = ajv.compile(generator.generate(registry));

    // Act
    const actual = validate(parse(text));

    // Assert
    (text.split('\n')[0] ?? '').should.equal('# yaml-language-server: $schema=./schema.json');
    actual.should.equal(valid);
    (validate.errors ?? []).map(error => `${error.instancePath} ${error.message}`).should.deepEqual(errors);
  });
});
