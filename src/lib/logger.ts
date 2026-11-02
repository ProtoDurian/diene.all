import { type DestinationStream, pino, destination as pinoDestination } from 'pino';

export interface ILogger {
  info(fields: Record<string, unknown>, message: string): void;
  warn(fields: Record<string, unknown>, message: string): void;
  error(fields: Record<string, unknown>, message: string): void;
}

export interface LoggerConfig {
  readonly level?: string;
  readonly destination?: DestinationStream;
}

export function createLogger(config: LoggerConfig = {}): ILogger {
  const { level = 'info', destination = pinoDestination({ fd: 1, sync: true }) } = config;

  return pino({ level }, destination);
}
