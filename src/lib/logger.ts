import { type DestinationStream, pino, destination as pinoDestination } from 'pino';

/** The logging surface injected into application adapters. */
export interface ILogger {
  info(fields: Record<string, unknown>, message: string): void;
  warn(fields: Record<string, unknown>, message: string): void;
  error(fields: Record<string, unknown>, message: string): void;
}

export interface LoggerConfig {
  /** Pino level name; anything below it is dropped. */
  readonly level?: string;
  /** Where records are written. Tests pass an in-memory sink; production writes to stdout. */
  readonly destination?: DestinationStream;
}

/** Build an independent logger with no module-level mutable instance. */
export function createLogger(config: LoggerConfig = {}): ILogger {
  const { level = 'info', destination = pinoDestination({ fd: 1, sync: true }) } = config;

  return pino({ level }, destination);
}
