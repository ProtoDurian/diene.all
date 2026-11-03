import { describe, it } from 'bun:test';
import 'should';
import { RedisKeyValueStore } from '../../src/adapters/kv/data/redis-kv-store';

/** A loopback port nothing listens on: bind an ephemeral port, then release it. */
function closedPort(): number {
  const server = Bun.listen({ hostname: '127.0.0.1', port: 0, socket: { data() {} } });
  const { port } = server;
  server.stop(true);
  return port;
}

describe('RedisKeyValueStore (unreachable backend)', () => {
  it('should reject the command instead of raising an unhandled connection error', async () => {
    // Arrange
    const subject = new RedisKeyValueStore({ host: '127.0.0.1', port: closedPort() });

    try {
      // Act
      const actual = subject.get('bun-cli:offline');

      // Assert
      await actual.should.be.rejected();
    } finally {
      await subject.close().catch(() => undefined);
    }
  }, 10_000);
});
