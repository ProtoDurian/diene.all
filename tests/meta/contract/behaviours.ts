import type { LoggerSink, MetricsCollector } from '@atomicloud/diene.interfaces';
import type { Result } from '@atomicloud/diene.result';
import type { TraceEmitter } from '../../../src/lib/trace-seam';

interface Seams {
  readonly logger: LoggerSink;
  readonly metrics: MetricsCollector;
  readonly traces: TraceEmitter;
}

type Outcome = 'ok' | Readonly<{ code: string; message: string }>;

async function outcome(result: Result<void, { code: string; message: string }>): Promise<Outcome> {
  if (await result.isOk()) return 'ok';
  const error = await result.unwrapErr();
  return { code: error.code, message: error.message };
}

async function runSeamScenarios(seams: Seams): Promise<readonly Outcome[]> {
  return [
    await outcome(seams.logger.emit({ level: 'info', message: 'ok', attributes: { a: 1 } })),
    await outcome(seams.logger.emit({ level: 'info', message: 'bad', attributes: { a: Number.NaN } })),
    await outcome(seams.logger.flush()),
    await outcome(seams.metrics.record({ kind: 'histogram', name: 'latency', value: 3, unit: 'ms' })),
    await outcome(seams.metrics.record({ kind: 'counter', name: 'jobs', value: Number.POSITIVE_INFINITY })),
    await outcome(seams.metrics.flush()),
    await outcome(seams.traces.emit({ name: 'work', events: [{ name: 'step' }], status: 'ok' })),
    await outcome(seams.traces.emit({ name: 'work', status: 'fine' as never })),
    await outcome(seams.traces.flush()),
  ];
}

export type { Seams };
export { runSeamScenarios };
