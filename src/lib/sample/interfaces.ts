export interface IKeyValueStore {
  set(key: string, value: string): Promise<void>;
  get(key: string): Promise<string | null>;
  close(): Promise<void>;
}

export interface ILogger {
  info(fields: Record<string, unknown>, message: string): void;
  warn(fields: Record<string, unknown>, message: string): void;
  error(fields: Record<string, unknown>, message: string): void;
}
