import { type DestinationStream, type Logger, pino, destination as pinoDestination } from 'pino';
import type { ILogger } from '../lib/sample/interfaces';

export interface PinoLoggerConfig {
  readonly level?: string;
  readonly destination?: DestinationStream;
}

export class PinoLogger implements ILogger {
  private readonly logger: Logger;

  constructor({ level = 'info', destination = pinoDestination({ fd: 1, sync: true }) }: PinoLoggerConfig = {}) {
    this.logger = pino({ level }, destination);
  }

  info(fields: Record<string, unknown>, message: string): void {
    this.logger.info(fields, message);
  }

  warn(fields: Record<string, unknown>, message: string): void {
    this.logger.warn(fields, message);
  }

  error(fields: Record<string, unknown>, message: string): void {
    this.logger.error(fields, message);
  }
}
