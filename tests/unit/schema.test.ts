import { describe, it } from 'bun:test';
import 'should';
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
