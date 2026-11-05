import {
  PortError,
  type LoggerSink,
  type MetricsCollector,
  type System,
  type Terminal,
  type VfsError,
  VfsPolicy,
  type VirtualFileSystem,
} from '@atomicloud/diene.interfaces';
import {
  InMemoryLoggerSink,
  InMemoryMetricsCollector,
  InMemorySystem,
  InMemoryTerminal,
  InMemoryVirtualFileSystem,
  type VfsCall,
} from '@atomicloud/diene.interfaces/test-helper';

function resolveThroughRequireTypes(): void {
  const failure: PortError<'vfs'> = new PortError('vfs', 'not-found', 'readFile', 'node16-cjs');
  const asError: VfsError = failure;

  const system: System = new InMemorySystem();
  const vfs: VirtualFileSystem = new InMemoryVirtualFileSystem();
  const terminal: Terminal = new InMemoryTerminal();
  const logger: LoggerSink = new InMemoryLoggerSink();
  const metrics: MetricsCollector = new InMemoryMetricsCollector();
  const recordedCalls: readonly VfsCall[] = new InMemoryVirtualFileSystem().calls;
  const policy: VfsPolicy = new VfsPolicy();

  void [asError, system, vfs, terminal, logger, metrics, recordedCalls, policy];
}

void resolveThroughRequireTypes;
