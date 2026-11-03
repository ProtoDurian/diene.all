import { describe, it } from 'bun:test';
import should from 'should';
import { SetController } from '../../src/adapters/kv/api/set-controller';
import { EXIT_ERROR, EXIT_OK } from '../../src/adapters/cli/exit-codes';
import { KvService } from '../../src/lib/kv/service';
import { FakeKeyValueStore, type SetCall, captureIo } from '../helpers/fakes';

describe('SetController', () => {
  describe('handle', () => {
    it('should write the composed key through the store and report success with exit 0', async () => {
      // Arrange
      const store = new FakeKeyValueStore();
      const io = captureIo();
      const subject = new SetController(new KvService(store), io);

      // Act
      const actual = await subject.handle('Bun Base', 'Sample Key', 'hello');

      // Assert
      actual.should.equal(EXIT_OK);
      store.setCalls.should.have.length(1);
      should(store.setCalls[0]).not.be.undefined();
      (store.setCalls[0] as SetCall).should.deepEqual({
        key: 'bun-base:sample-key',
        value: 'hello',
        ttlSeconds: undefined,
      });
      io.successes.should.deepEqual(['set bun-base:sample-key = hello']);
      io.errors.should.be.empty();
    });

    it('should pass the parsed ttl through and note the expiry in the success message', async () => {
      // Arrange
      const store = new FakeKeyValueStore();
      const io = captureIo();
      const subject = new SetController(new KvService(store), io);

      // Act
      const actual = await subject.handle('ns', 'key', 'v', '60');

      // Assert
      actual.should.equal(EXIT_OK);
      should(store.setCalls[0]?.ttlSeconds).not.be.undefined();
      (store.setCalls[0]?.ttlSeconds as number).should.equal(60);
      io.successes.should.deepEqual(['set ns:key = v (expires in 60s)']);
    });

    it.each(['abc', '1.5', '0', '-1', '0x10', '1e2', String(365 * 24 * 60 * 60 + 1)])(
      'should reject invalid --ttl "%s" with exit 1 and not touch the store',
      async input => {
        // Arrange
        const store = new FakeKeyValueStore();
        const io = captureIo();
        const subject = new SetController(new KvService(store), io);

        // Act
        const actual = await subject.handle('ns', 'key', 'v', input);

        // Assert
        actual.should.equal(EXIT_ERROR);
        store.setCalls.should.be.empty();
        should(io.errors[0]).not.be.undefined();
        (io.errors[0] as string).should.containEql('invalid input');
      },
    );

    it('should reject a namespace that slugifies to empty as invalid input', async () => {
      // Arrange
      const store = new FakeKeyValueStore();
      const io = captureIo();
      const subject = new SetController(new KvService(store), io);
      const input = '!!!';

      // Act
      const actual = await subject.handle(input, 'key', 'v');

      // Assert
      actual.should.equal(EXIT_ERROR);
      store.setCalls.should.be.empty();
      should(io.errors[0]).not.be.undefined();
      (io.errors[0] as string).should.containEql('invalid input');
    });

    it('should report an unreachable backend with exit 1 when the store fails', async () => {
      // Arrange
      const store = new FakeKeyValueStore({}, new Error('connect ECONNREFUSED 127.0.0.1:6379'));
      const io = captureIo();
      const subject = new SetController(new KvService(store), io);

      // Act
      const actual = await subject.handle('ns', 'key', 'v');

      // Assert
      actual.should.equal(EXIT_ERROR);
      should(io.errors[0]).not.be.undefined();
      (io.errors[0] as string).should.containEql('failed to reach key-value backend');
    });
  });
});
