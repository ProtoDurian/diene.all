import type { Result } from '@atomicloud/diene.result';
import { type LoggingError, PortError } from './error.js';
import { type TelemetryAttributes, TelemetryPolicy } from './telemetry.js';
import { type Checked, PortPolicy } from './validation.js';

type LogLevel = 'debug' | 'error' | 'fatal' | 'info' | 'trace' | 'warn';

interface LogRecord {
  readonly level: LogLevel;
  readonly message: string;
  readonly attributes?: TelemetryAttributes;
}

interface LoggerSink {
  emit(record: LogRecord): Result<void, LoggingError>;
  flush(): Result<void, LoggingError>;
}

class LoggingPolicy extends PortPolicy {
  constructor(private readonly telemetry: TelemetryPolicy = new TelemetryPolicy()) {
    super();
  }

  checkRecord(record: LogRecord): Checked<Readonly<LogRecord>, LoggingError> {
    if (typeof record !== 'object' || record === null) {
      return this.reject(new PortError('logging', 'invalid-input', 'emit', 'Log record must be an object'));
    }
    if (!['trace', 'debug', 'info', 'warn', 'error', 'fatal'].includes(record.level)) {
      return this.reject(new PortError('logging', 'invalid-input', 'emit', 'Log level is invalid', { field: 'level' }));
    }
    if (typeof record.message !== 'string' || record.message.trim() === '') {
      return this.reject(
        new PortError('logging', 'invalid-input', 'emit', 'Log message must not be blank', { field: 'message' }),
      );
    }
    const attributes = this.telemetry.checkAttributes(record.attributes, 'logging', 'emit');
    if (!attributes.ok) return attributes;
    return this.accept(
      Object.freeze({
        ...(attributes.value === undefined ? {} : { attributes: attributes.value }),
        level: record.level,
        message: record.message,
      }),
    );
  }

  validateRecord(record: LogRecord): Result<Readonly<LogRecord>, LoggingError> {
    return this.toResult(this.checkRecord(record));
  }
}

export type { LoggerSink, LogLevel, LogRecord };
export { LoggingPolicy };
