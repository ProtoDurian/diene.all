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
