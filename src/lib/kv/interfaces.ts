export interface IKeyValueStore {
  set(key: string, value: string, ttlSeconds?: number): Promise<void>;
  get(key: string): Promise<string | null>;
  delete(key: string): Promise<void>;
  close(): Promise<void>;
}

export interface IProgressReporter {
  start(total: number): void;
  tick(): void;
  stop(): void;
}

export interface IShell {
  platform(): Promise<string>;
}
