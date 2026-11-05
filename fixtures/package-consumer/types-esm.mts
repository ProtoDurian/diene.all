import {
  PortError,
  portError,
  type LoggerSink,
  type MetricsCollector,
  type System,
  type Terminal,
  type VfsError,
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

const failure: PortError<'vfs'> = portError('vfs', 'not-found', 'readFile', 'node16-esm');
const asError: VfsError = failure;

const system: System = new InMemorySystem();
const vfs: VirtualFileSystem = new InMemoryVirtualFileSystem();
const terminal: Terminal = new InMemoryTerminal();
const logger: LoggerSink = new InMemoryLoggerSink();
const metrics: MetricsCollector = new InMemoryMetricsCollector();
const recordedCalls: readonly VfsCall[] = new InMemoryVirtualFileSystem().calls;

void [asError, system, vfs, terminal, logger, metrics, recordedCalls];
