import { describe, it } from 'bun:test';
import 'should';
import type { z } from 'zod';
import { FrozenConfig } from '../../src/lib/config.js';

type Shape = { server: z.ZodType<{ port: number }>; client: z.ZodType<{ name: string }> };

describe('FrozenConfig', () => {
  it('should serve one block by key and every block via all', () => {
    // Arrange
    const config = new FrozenConfig<Shape>({ server: { port: 80 }, client: { name: 'app' } });

    // Act
    const server = config.get('server');
    const all = config.all();

    // Assert
    server.should.deepEqual({ port: 80 });
    all.should.deepEqual({ server: { port: 80 }, client: { name: 'app' } });
  });

  it('should freeze the served object without freezing the caller input', () => {
    // Arrange
    const input = { server: { port: 80 }, client: { name: 'app' } };

    // Act
    const all = new FrozenConfig<Shape>(input).all();

    // Assert
    Object.isFrozen(all).should.be.true();
    Object.isFrozen(input).should.be.false();
  });
});

describe('FrozenConfig deep freeze', () => {
  type Nested = { server: z.ZodType<{ port: number; tags: string[]; tls: { ca: string[] } }> };

  it('should freeze every nested object and array', () => {
    // Arrange
    const config = new FrozenConfig<Nested>({ server: { port: 80, tags: ['a'], tls: { ca: ['x'] } } });

    // Act
    const server = config.get('server');

    // Assert
    [server, server.tags, server.tls, server.tls.ca]
      .map(node => Object.isFrozen(node))
      .should.deepEqual([true, true, true, true]);
  });

  it('should leave the caller input mutable', () => {
    // Arrange
    const input = { server: { port: 80, tags: ['a'], tls: { ca: ['x'] } } };

    // Act
    new FrozenConfig<Nested>(input);

    // Assert
    [input.server, input.server.tags, input.server.tls]
      .map(node => Object.isFrozen(node))
      .should.deepEqual([false, false, false]);
  });
});
