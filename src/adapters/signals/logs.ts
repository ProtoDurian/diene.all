import {
  checkLogRecord,
  type LoggerSink,
  type LoggingError,
  type LogRecord,
  portError,
  type TelemetryAttributes,
} from '@atomicloud/diene.interfaces';
import { Err, Ok, type Result } from '@atomicloud/diene.result';
import { context, isSpanContextValid, type SpanContext, trace } from '@opentelemetry/api';
import pino, { type DestinationStream, type Logger } from 'pino';

const OTLP_LOGS_BRIDGE_STATUS = 'stubbed' as const;

interface LoggerSignal {
  readonly active: boolean;
  readonly logger: Logger;
  readonly sink: LoggerSink;
  readonly otlpBridge: typeof OTLP_LOGS_BRIDGE_STATUS;
}

class TraceContextFields {
  constructor(
    private readonly current: () => SpanContext | undefined = () => trace.getSpan(context.active())?.spanContext(),
  ) {}

  fields(): Record<string, number | string> {
    const spanContext = this.current();
    if (spanContext === undefined || !isSpanContextValid(spanContext)) return {};
    return { span_id: spanContext.spanId, trace_flags: spanContext.traceFlags, trace_id: spanContext.traceId };
  }
}

class PinoLoggerSink implements LoggerSink {
  constructor(private readonly logger: Logger) {}

  emit(record: LogRecord): Result<void, LoggingError> {
    const checked = checkLogRecord(record);
    if (!checked.ok) return Err(checked.error);
    try {
      this.logger[checked.value.level](checked.value.attributes ?? {}, checked.value.message);
      return Ok(undefined);
    } catch (cause) {
      return Err(this.failure('emit', 'Pino failed to emit the log record', cause));
    }
  }

  flush(): Result<void, LoggingError> {
    try {
      this.logger.flush();
      return Ok(undefined);
    } catch (cause) {
      return Err(this.failure('flush', 'Pino failed to flush', cause));
    }
  }

  private failure(operation: string, message: string, cause: unknown): LoggingError {
    return portError('logging', 'io', operation, message, {
      cause: cause instanceof Error ? cause.message : String(cause),
    });
  }
}

class LoggerSignalFactory {
  constructor(private readonly traceContext: TraceContextFields = new TraceContextFields()) {}

  create(active: boolean, resource: TelemetryAttributes, destination?: DestinationStream): LoggerSignal {
    const options: pino.LoggerOptions = {
      base: { ...resource },
      enabled: active,
      level: 'trace',
      mixin: () => this.traceContext.fields(),
    };
    const logger = destination === undefined ? pino(options) : pino(options, destination);
    return Object.freeze({ active, logger, otlpBridge: OTLP_LOGS_BRIDGE_STATUS, sink: new PinoLoggerSink(logger) });
  }
}

export type { LoggerSignal };
export { LoggerSignalFactory, OTLP_LOGS_BRIDGE_STATUS, PinoLoggerSink, TraceContextFields };
