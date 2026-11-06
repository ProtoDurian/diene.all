import { describe, it } from 'bun:test';
import should from 'should';
import { DoctorService } from '../../../src/lib/kv/doctor-service';
import { FakeKeyValueStore, FakeShell } from '../../helpers/fakes';

describe('DoctorService', () => {
  describe('platform', () => {
    it('should return the string reported by the shell', async () => {
      // Arrange
      const expected = 'Darwin 25.0.0 arm64';
      const subject = new DoctorService(new FakeKeyValueStore(), new FakeShell(expected));

      // Act
      const actual = await subject.platform();

      // Assert
      actual.should.equal(expected);
    });
  });

  describe('probeBackend', () => {
    it('should round-trip a unique probe without overwriting a user-owned key', async () => {
      // Arrange
      const userKey = 'doctor:probe';
      const store = new FakeKeyValueStore({ [userKey]: 'user-owned' });
      const subject = new DoctorService(store, new FakeShell('Linux'));

      // Act
      const actual = await subject.probeBackend();

      // Assert
      actual.should.be.true();
      const probeKey = store.setCalls[0]?.key ?? '';
      probeKey.should.match(/^doctor:probe-/);
      probeKey.should.not.equal(userKey);
      should(store.setCalls[0]?.ttlSeconds).not.be.undefined();
      (store.setCalls[0]?.ttlSeconds as number).should.equal(30);
      store.getCalls.should.deepEqual([probeKey]);
      store.deleteCalls.should.deepEqual([probeKey]);
      const userValue = await store.get(userKey);
      should(userValue).not.be.null();
      (userValue as string).should.equal('user-owned');
    });

    it('should propagate the error when the store fails', async () => {
      // Arrange
      const expected = new Error('connection refused');
      const store = new FakeKeyValueStore({}, expected);
      const subject = new DoctorService(store, new FakeShell('Linux'));

      // Act
      const actual = subject.probeBackend();

      // Assert
      await actual.should.be.rejectedWith(expected);
    });

    it('should still report a healthy backend when the probe cleanup fails', async () => {
      // Arrange
      class FailingDeleteStore extends FakeKeyValueStore {
        override async delete(): Promise<void> {
          throw new Error('delete refused');
        }
      }
      const store = new FailingDeleteStore();
      const subject = new DoctorService(store, new FakeShell('Linux'));

      // Act
      const actual = await subject.probeBackend();

      // Assert
      actual.should.be.true();
    });
  });
});
