import type { IKeyValueStore } from './interfaces';
import type { KeyComposer } from './key';

export class SampleService {
  constructor(
    private readonly store: IKeyValueStore,
    private readonly keys: KeyComposer,
  ) {}

  async roundTrip(key: string, value: string): Promise<string | null> {
    const composed = this.keys.compose(key);
    await this.store.set(composed, value);
    return this.store.get(composed);
  }
}
