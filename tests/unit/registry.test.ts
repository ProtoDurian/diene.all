import { describe, it } from 'bun:test';
import 'should';
import { z } from 'zod';
import { ConfigRegistry, ConfigRegistryError } from '../../src/lib/registry.js';

describe('ConfigRegistry', () => {
  it('should start empty and register blocks immutably', () => {
    // Arrange
    const empty = ConfigRegistry.create();

    // Act
    const registry = empty.register('server', z.object({ port: z.number() }));

    // Assert
    empty.keys.should.deepEqual([]);
    registry.keys.should.deepEqual(['server']);
  });

  it('should compose a root schema of every registered block', () => {
    // Arrange
    const registry = ConfigRegistry.create()
      .register('server', z.object({ port: z.number() }))
      .register('client', z.object({ name: z.string() }));

    // Act
    const actual = registry.rootSchema().parse({ server: { port: 8080 }, client: { name: 'app' } });

    // Assert
    actual.should.deepEqual({ server: { port: 8080 }, client: { name: 'app' } });
  });

  it('should throw ConfigRegistryError on a duplicate key', () => {
    // Arrange
    const registry = ConfigRegistry.create().register('server', z.object({ port: z.number() }));

    // Act
    const act = () => registry.register('server', z.object({ host: z.string() }));

    // Assert
    act.should.throw(ConfigRegistryError, { message: 'config block "server" is already registered' });
  });
});
