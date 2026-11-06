/** Tenant-scoped key/value store with expiry; swap the adapter to change the backend. */
export interface ICacheStore {
  get(key: string): Promise<unknown>;
  set(key: string, value: unknown, ttlSeconds: number): Promise<void>;
  delete(key: string): Promise<void>;
}
