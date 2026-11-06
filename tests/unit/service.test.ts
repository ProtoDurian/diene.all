import { describe, it } from 'bun:test';
import should from 'should';
import type { IKeyValueStore } from '../../src/lib/sample/interfaces';
import { KeyComposer } from '../../src/lib/sample/key';
import { SampleService } from '../../src/lib/sample/service';

class MemoryKeyValueStore implements IKeyValueStore {
  readonly entries = new Map<string, string>();

  async set(key: string, value: string): Promise<void> {
    this.entries.set(key, value);
  }

  async get(key: string): Promise<string | null> {
    return this.entries.get(key) ?? null;
  }

  async close(): Promise<void> {}
}

describe('SampleService', () => {
  it('should store the value under the composed key and read it back', async () => {
    // Arrange
    const store = new MemoryKeyValueStore();
    const subject = new SampleService(store, new KeyComposer('Bun Base'));
    const expected = 'sample value';

    // Act
    const actual = await subject.roundTrip('sample key', expected);

    // Assert
    should(actual).not.be.null();
    (actual as string).should.equal(expected);
    [...store.entries.keys()].should.deepEqual(['bun-base:sample-key']);
  });
});
