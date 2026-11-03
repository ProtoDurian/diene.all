import { describe, it } from 'bun:test';
import should from 'should';
import { KvService } from '../../../src/lib/kv/service';
import { FakeKeyValueStore, type SetCall, captureProgress } from '../../helpers/fakes';

describe('KvService', () => {
  describe('setValue', () => {
    it('should compose the namespaced key via slug and write it through the store', async () => {
      // Arrange
      const store = new FakeKeyValueStore();
      const subject = new KvService(store);
      const expected = 'bun-base:sample-key';

      // Act
      const actual = await subject.setValue('Bun Base', 'Sample Key', 'hello');

      // Assert
      actual.should.equal(expected);
      store.setCalls.should.have.length(1);
      should(store.setCalls[0]).not.be.undefined();
      (store.setCalls[0] as SetCall).should.deepEqual({ key: expected, value: 'hello', ttlSeconds: undefined });
    });

    it('should pass the ttl through to the store', async () => {
      // Arrange
      const store = new FakeKeyValueStore();
      const subject = new KvService(store);
      const input = 60;

      // Act
      await subject.setValue('ns', 'key', 'v', input);

      // Assert
      should(store.setCalls[0]?.ttlSeconds).not.be.undefined();
      (store.setCalls[0]?.ttlSeconds as number).should.equal(input);
    });
  });

  describe('getValue', () => {
    it('should return the composed key and the stored value', async () => {
      // Arrange
      const store = new FakeKeyValueStore({ 'ns:key': 'hello' });
      const subject = new KvService(store);
      const expected = { composed: 'ns:key', value: 'hello' };

      // Act
      const actual = await subject.getValue('ns', 'key');

      // Assert
      actual.should.deepEqual(expected);
      store.getCalls.should.deepEqual(['ns:key']);
    });

    it('should return a null value for a missing key', async () => {
      // Arrange
      const store = new FakeKeyValueStore();
      const subject = new KvService(store);
      const expected = { composed: 'ns:missing', value: null };

      // Act
      const actual = await subject.getValue('ns', 'missing');

      // Assert
      actual.should.deepEqual(expected);
    });
  });

  describe('seed', () => {
    it('should write N entries, start progress with the total, tick N times, and stop', async () => {
      // Arrange
      const store = new FakeKeyValueStore();
      const progress = captureProgress();
      const subject = new KvService(store);
      const input = 3;

      // Act
      await subject.seed('ns', input, progress);

      // Assert
      store.setCalls.should.have.length(input);
      store.setCalls.map(call => call.key).should.deepEqual(['ns:sample-1', 'ns:sample-2', 'ns:sample-3']);
      store.setCalls.map(call => call.value).should.deepEqual(['value-1', 'value-2', 'value-3']);
      progress.totals.should.deepEqual([input]);
      progress.ticks.should.equal(input);
      progress.stopped.should.be.true();
    });

    it('should stop the progress reporter and propagate the error when the store throws mid-way', async () => {
      // Arrange
      const expected = new Error('connect ECONNREFUSED 127.0.0.1:6379');
      const store = new FakeKeyValueStore({}, expected);
      const progress = captureProgress();
      const subject = new KvService(store);

      // Act
      const actual = subject.seed('ns', 3, progress);

      // Assert
      await actual.should.be.rejectedWith(expected);
      progress.stopped.should.be.true();
    });
  });
});
