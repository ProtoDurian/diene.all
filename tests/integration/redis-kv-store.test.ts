import { afterAll, beforeAll, describe, it } from 'bun:test';
import type { TCPSocketListener } from 'bun';
import should from 'should';
import { GenericContainer, type StartedTestContainer, Wait } from 'testcontainers';
import { RedisKeyValueStore } from '../../src/adapters/redis-kv-store';
import type { ILogger } from '../../src/lib/sample/interfaces';
import { KeyComposer } from '../../src/lib/sample/key';
import { SampleService } from '../../src/lib/sample/service';

interface RecordedLog {
  readonly fields: Record<string, unknown>;
  readonly message: string;
}

interface RecordingLogger {
  readonly logger: ILogger;
  readonly errors: RecordedLog[];
  readonly firstError: Promise<RecordedLog>;
}

function recordingLogger(): RecordingLogger {
  const errors: RecordedLog[] = [];
  let announce: (entry: RecordedLog) => void = () => undefined;
  const firstError = new Promise<RecordedLog>(resolve => {
    announce = resolve;
  });

  return {
    errors,
    firstError,
    logger: {
      info: () => undefined,
      warn: () => undefined,
      error: (fields, message) => {
        const entry = { fields, message };
        errors.push(entry);
        announce(entry);
      },
    },
  };
}

describe('RedisKeyValueStore (Testcontainers)', () => {
  let container: StartedTestContainer;
  let store: RedisKeyValueStore;
  let observed: RecordingLogger;
  let subject: SampleService;

  beforeAll(async () => {
    container = await new GenericContainer('redis:7.4.5-alpine')
      .withExposedPorts(6379)
      .withWaitStrategy(Wait.forLogMessage(/Ready to accept connections/))
      .start();
    observed = recordingLogger();
    store = new RedisKeyValueStore({ host: container.getHost(), port: container.getMappedPort(6379) }, observed.logger);
    subject = new SampleService(store, new KeyComposer('Bun Base'));
  }, 120_000);

  afterAll(async () => {
    await store?.close();
    await container?.stop();
  }, 120_000);

  it('should persist and retrieve a namespaced value', async () => {
    // Arrange
    const expected = 'hello';

    // Act
    const actual = await subject.roundTrip('sample key', expected);

    // Assert
    should(actual).not.be.null();
    (actual as string).should.equal(expected);
  });

  it('should overwrite the value already stored under a key', async () => {
    // Arrange
    const expected = 'second';
    await subject.roundTrip('overwrite', 'first');

    // Act
    const actual = await subject.roundTrip('overwrite', expected);

    // Assert
    should(actual).not.be.null();
    (actual as string).should.equal(expected);
  });

  it('should return null for an unknown key', async () => {
    // Act
    const actual = await store.get('bun-base:missing');

    // Assert
    should(actual).be.null();
  });

  it('should log nothing while the connection is healthy', () => {
    // Assert
    observed.errors.should.deepEqual([]);
  });
});

describe('RedisKeyValueStore against an endpoint that is not Redis', () => {
  let rogue: TCPSocketListener | undefined;
  let subject: RedisKeyValueStore | undefined;

  afterAll(async () => {
    await subject?.close().catch(() => undefined);
    rogue?.stop(true);
  }, 30_000);

  it('should report the failure through the injected logger instead of the console', async () => {
    // Arrange
    // Invalid RESP bytes hit the non-ECONNREFUSED branch deterministically.
    const observed = recordingLogger();
    const listener: TCPSocketListener = Bun.listen({
      hostname: '127.0.0.1',
      port: 0,
      socket: {
        data: socket => {
          socket.write('this is not a RESP reply\r\n');
        },
      },
    });
    rogue = listener;
    subject = new RedisKeyValueStore({ host: '127.0.0.1', port: listener.port }, observed.logger);

    // Act
    const attempt = subject.get('bun-base:protocol').catch(() => null);
    const actual = await observed.firstError;

    // Assert
    actual.message.should.equal('unexpected redis connection error');
    actual.fields.should.have.properties({ host: '127.0.0.1', port: listener.port });
    actual.fields.should.have.property('reason').which.is.a.String();
    await attempt;
  }, 30_000);
});
