import type { IKeyValueStore, IShell } from './interfaces';
import { namespacedKey } from './slug';

export class DoctorService {
  constructor(
    private readonly store: IKeyValueStore,
    private readonly shell: IShell,
  ) {}

  async platform(): Promise<string> {
    return this.shell.platform();
  }

  async probeBackend(): Promise<boolean> {
    const probe = namespacedKey('doctor', `probe-${crypto.randomUUID()}`);
    // TTL is a cleanup backstop; the normal path removes the unique key immediately.
    await this.store.set(probe, 'ok', 30);
    try {
      return (await this.store.get(probe)) === 'ok';
    } finally {
      // Cleanup must never mask a backend error; the TTL bounds any failed deletion.
      await this.store.delete(probe).catch(() => undefined);
    }
  }
}
