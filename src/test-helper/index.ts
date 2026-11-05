import {
  type CreateDirectoryOptions,
  type LoggerSink,
  type LoggingError,
  LoggingPolicy,
  type LogRecord,
  type MetricRecord,
  type MetricsCollector,
  type MetricsError,
  MetricsPolicy,
  PortError,
  type ProcessOutput,
  type ProcessRequest,
  type RemoveOptions,
  type System,
  type SystemError,
  SystemPolicy,
  type Terminal,
  type TerminalError,
  TerminalPolicy,
  type TerminalRead,
  type TerminalWrite,
  type VfsEntry,
  type VfsError,
  VfsPolicy,
  type VfsStat,
  type VirtualFileSystem,
} from '@atomicloud/diene.interfaces';
import { Err, Ok, type Result } from '@atomicloud/diene.result';

interface SequencedCall {
  readonly sequence: number;
}

interface SystemCall extends SequencedCall {
  readonly method: 'execute';
  readonly request: ProcessRequest;
}

type VfsCall =
  | (SequencedCall & {
      readonly method: 'createDirectory';
      readonly path: string;
      readonly options: CreateDirectoryOptions;
    })
  | (SequencedCall & { readonly method: 'exists'; readonly path: string })
  | (SequencedCall & { readonly method: 'list'; readonly path: string })
  | (SequencedCall & { readonly method: 'readFile'; readonly path: string })
  | (SequencedCall & { readonly method: 'remove'; readonly path: string; readonly options: RemoveOptions })
  | (SequencedCall & { readonly method: 'stat'; readonly path: string })
  | (SequencedCall & { readonly method: 'writeFile'; readonly path: string; readonly contents: Uint8Array });

type TerminalCall =
  | (SequencedCall & { readonly method: 'readLine'; readonly input: Readonly<TerminalRead> })
  | (SequencedCall & { readonly method: 'write'; readonly output: Required<TerminalWrite> });

type LoggerCall =
  | (SequencedCall & { readonly method: 'emit'; readonly record: Readonly<LogRecord> })
  | (SequencedCall & { readonly method: 'flush' });

type MetricsCall =
  | (SequencedCall & { readonly method: 'flush' })
  | (SequencedCall & { readonly method: 'record'; readonly metric: Readonly<MetricRecord> });

type MemoryNode = { readonly kind: 'directory' } | { readonly contents: Uint8Array; readonly kind: 'file' };

class Snapshot {
  comparable(value: unknown): unknown {
    if (value instanceof Uint8Array) {
      return { bytes: Array.from(value) };
    }
    if (Array.isArray(value)) {
      return value.map(entry => this.comparable(entry));
    }
    if (typeof value === 'object' && value !== null) {
      return Object.fromEntries(
        Object.entries(value)
          .sort(([left], [right]) => (left === right ? 0 : left < right ? -1 : 1))
          .map(([key, entry]) => [key, this.comparable(entry)]),
      );
    }
    return value;
  }

  assertEqual(label: string, actual: unknown, expected: unknown): void {
    if (JSON.stringify(this.comparable(actual)) !== JSON.stringify(this.comparable(expected))) {
      throw new InterfaceAssertionError(label, expected, actual);
    }
  }
}

class InterfaceAssertionError extends Error {
  constructor(
    readonly label: string,
    readonly expected: unknown,
    readonly actual: unknown,
  ) {
    super(
      `${label} mismatch\nExpected: ${JSON.stringify(new Snapshot().comparable(expected))}\nActual: ${JSON.stringify(new Snapshot().comparable(actual))}`,
    );
    this.name = 'InterfaceAssertionError';
  }
}

class InMemorySystem implements System {
  private readonly recordedCalls: SystemCall[] = [];
  private readonly outcomes: Result<ProcessOutput, SystemError>[];
  private readonly snapshot = new Snapshot();
  private sequence = 0;

  constructor(
    outcomes: readonly Result<ProcessOutput, SystemError>[] = [],
    private readonly policy: SystemPolicy = new SystemPolicy(),
  ) {
    this.outcomes = [...outcomes];
  }

  get calls(): readonly SystemCall[] {
    return this.recordedCalls.map(call =>
      Object.freeze({ ...call, request: InMemorySystem.cloneRequest(call.request) }),
    );
  }

  enqueue(outcome: Result<ProcessOutput, SystemError>): void {
    this.outcomes.push(outcome);
  }

  execute(request: ProcessRequest): Result<ProcessOutput, SystemError> {
    const checked = this.policy.checkRequest(request);
    if (!checked.ok) return Err(checked.error);
    const validated = checked.value;
    this.recordedCalls.push(
      Object.freeze({ method: 'execute', request: InMemorySystem.cloneRequest(validated), sequence: this.sequence++ }),
    );
    const outcome = this.outcomes.shift();
    if (outcome === undefined) {
      return Err(
        new PortError('system', 'unexpected-call', 'execute', 'No process outcome was queued', {
          executable: validated.executable,
        }),
      );
    }
    return outcome.andThen(output => this.policy.validateOutput(output));
  }

  assertCalls(expected: readonly ProcessRequest[]): void {
    this.snapshot.assertEqual(
      'System calls',
      this.calls.map(call => call.request),
      expected,
    );
  }

  private static cloneRequest(request: ProcessRequest): ProcessRequest {
    return Object.freeze({
      executable: request.executable,
      ...(request.arguments === undefined ? {} : { arguments: Object.freeze([...request.arguments]) }),
      ...(request.cwd === undefined ? {} : { cwd: request.cwd }),
      ...(request.environment === undefined ? {} : { environment: Object.freeze({ ...request.environment }) }),
      ...(request.stdin === undefined ? {} : { stdin: request.stdin }),
      ...(request.timeoutMs === undefined ? {} : { timeoutMs: request.timeoutMs }),
    });
  }
}

class InMemoryVirtualFileSystem implements VirtualFileSystem {
  private readonly nodes = new Map<string, MemoryNode>([['/', Object.freeze({ kind: 'directory' })]]);
  private readonly recordedCalls: VfsCall[] = [];
  private nextFailure: VfsError | undefined;
  private readonly snapshot = new Snapshot();
  private sequence = 0;

  constructor(private readonly policy: VfsPolicy = new VfsPolicy()) {}

  get calls(): readonly VfsCall[] {
    return this.recordedCalls.map(call =>
      call.method === 'writeFile'
        ? Object.freeze({ ...call, contents: new Uint8Array(call.contents) })
        : Object.freeze({ ...call }),
    );
  }

  get files(): Readonly<Record<string, Uint8Array>> {
    return Object.freeze(
      Object.fromEntries(
        [...this.nodes.entries()]
          .filter((entry): entry is [string, Extract<MemoryNode, { kind: 'file' }>] => entry[1].kind === 'file')
          .sort(([left], [right]) => (left === right ? 0 : left < right ? -1 : 1))
          .map(([path, node]) => [path, new Uint8Array(node.contents)]),
      ),
    );
  }

  failNext(error: VfsError): void {
    this.nextFailure = error;
  }

  readFile(path: string): Result<Uint8Array, VfsError> {
    const checked = this.policy.checkPath(path, 'readFile');
    if (!checked.ok) return Err(checked.error);
    const validPath = checked.value;
    this.recordedCalls.push(Object.freeze({ method: 'readFile', path: validPath, sequence: this.sequence++ }));
    const failure = this.takeFailure() ?? this.fileAncestorError('readFile', validPath);
    if (failure !== undefined) return Err(failure);
    const node = this.nodes.get(validPath);
    if (node === undefined) return Err(new PortError('vfs', 'not-found', 'readFile', `File not found: ${validPath}`));
    if (node.kind !== 'file')
      return Err(new PortError('vfs', 'not-a-file', 'readFile', `Path is not a file: ${validPath}`));
    return Ok(new Uint8Array(node.contents));
  }

  writeFile(path: string, contents: Uint8Array): Result<void, VfsError> {
    const checkedPath = this.policy.checkPath(path, 'writeFile');
    if (!checkedPath.ok) return Err(checkedPath.error);
    const checkedContents = this.policy.checkContents(contents);
    if (!checkedContents.ok) return Err(checkedContents.error);
    const validPath = checkedPath.value;
    const validContents = checkedContents.value;
    this.recordedCalls.push(
      Object.freeze({
        contents: new Uint8Array(validContents),
        method: 'writeFile',
        path: validPath,
        sequence: this.sequence++,
      }),
    );
    const failure = this.takeFailure() ?? this.fileAncestorError('writeFile', validPath);
    if (failure !== undefined) return Err(failure);
    if (this.nodes.get(validPath)?.kind === 'directory') {
      return Err(new PortError('vfs', 'not-a-file', 'writeFile', `Path is not a file: ${validPath}`));
    }
    if (!this.nodes.has(InMemoryVirtualFileSystem.parentPath(validPath))) {
      return Err(new PortError('vfs', 'not-found', 'writeFile', `Parent directory does not exist: ${validPath}`));
    }
    this.nodes.set(validPath, Object.freeze({ contents: new Uint8Array(validContents), kind: 'file' }));
    return Ok(undefined);
  }

  exists(path: string): Result<boolean, VfsError> {
    const checked = this.policy.checkPath(path, 'exists');
    if (!checked.ok) return Err(checked.error);
    const validPath = checked.value;
    this.recordedCalls.push(Object.freeze({ method: 'exists', path: validPath, sequence: this.sequence++ }));
    const failure = this.takeFailure();
    return failure === undefined ? Ok(this.nodes.has(validPath)) : Err(failure);
  }

  stat(path: string): Result<VfsStat, VfsError> {
    const checked = this.policy.checkPath(path, 'stat');
    if (!checked.ok) return Err(checked.error);
    const validPath = checked.value;
    this.recordedCalls.push(Object.freeze({ method: 'stat', path: validPath, sequence: this.sequence++ }));
    const failure = this.takeFailure() ?? this.fileAncestorError('stat', validPath);
    if (failure !== undefined) return Err(failure);
    const node = this.nodes.get(validPath);
    if (node === undefined) return Err(new PortError('vfs', 'not-found', 'stat', `Path not found: ${validPath}`));
    return Ok(Object.freeze({ kind: node.kind, size: node.kind === 'file' ? node.contents.byteLength : 0 }));
  }

  list(path: string): Result<readonly VfsEntry[], VfsError> {
    const checked = this.policy.checkPath(path, 'list');
    if (!checked.ok) return Err(checked.error);
    const validPath = checked.value;
    this.recordedCalls.push(Object.freeze({ method: 'list', path: validPath, sequence: this.sequence++ }));
    const failure = this.takeFailure() ?? this.fileAncestorError('list', validPath);
    if (failure !== undefined) return Err(failure);
    const node = this.nodes.get(validPath);
    if (node === undefined) return Err(new PortError('vfs', 'not-found', 'list', `Directory not found: ${validPath}`));
    if (node.kind !== 'directory') {
      return Err(new PortError('vfs', 'not-a-directory', 'list', `Path is not a directory: ${validPath}`));
    }
    const prefix = validPath === '/' ? '/' : `${validPath}/`;
    const entries = [...this.nodes.entries()]
      .filter(([candidate]) => candidate.startsWith(prefix) && candidate !== validPath)
      .map(([candidate, child]) => ({ child, remainder: candidate.slice(prefix.length) }))
      .filter(({ remainder }) => remainder !== '' && !remainder.includes('/'))
      .map(({ child, remainder }) => Object.freeze({ kind: child.kind, name: remainder }))
      .sort((left, right) => (left.name === right.name ? 0 : left.name < right.name ? -1 : 1));
    return Ok(Object.freeze(entries));
  }

  createDirectory(path: string, options: CreateDirectoryOptions = {}): Result<void, VfsError> {
    const checkedPath = this.policy.checkPath(path, 'createDirectory');
    if (!checkedPath.ok) return Err(checkedPath.error);
    const checkedOptions = this.policy.checkCreateDirectoryOptions(options);
    if (!checkedOptions.ok) return Err(checkedOptions.error);
    const validPath = checkedPath.value;
    const normalizedOptions = checkedOptions.value;
    this.recordedCalls.push(
      Object.freeze({
        method: 'createDirectory',
        options: normalizedOptions,
        path: validPath,
        sequence: this.sequence++,
      }),
    );
    const failure = this.takeFailure() ?? this.fileAncestorError('createDirectory', validPath);
    if (failure !== undefined) return Err(failure);
    const existing = this.nodes.get(validPath);
    if (existing !== undefined) {
      return existing.kind === 'directory' && normalizedOptions.recursive
        ? Ok(undefined)
        : Err(new PortError('vfs', 'already-exists', 'createDirectory', `Path already exists: ${validPath}`));
    }
    if (!normalizedOptions.recursive && !this.nodes.has(InMemoryVirtualFileSystem.parentPath(validPath))) {
      return Err(new PortError('vfs', 'not-found', 'createDirectory', `Parent directory does not exist: ${validPath}`));
    }
    for (const directory of [...InMemoryVirtualFileSystem.ancestors(validPath), validPath]) {
      if (!this.nodes.has(directory)) this.nodes.set(directory, Object.freeze({ kind: 'directory' }));
    }
    return Ok(undefined);
  }

  remove(path: string, options: RemoveOptions = {}): Result<void, VfsError> {
    const checkedPath = this.policy.checkPath(path, 'remove');
    if (!checkedPath.ok) return Err(checkedPath.error);
    const checkedOptions = this.policy.checkRemoveOptions(options);
    if (!checkedOptions.ok) return Err(checkedOptions.error);
    const validPath = checkedPath.value;
    const normalizedOptions = checkedOptions.value;
    this.recordedCalls.push(
      Object.freeze({ method: 'remove', options: normalizedOptions, path: validPath, sequence: this.sequence++ }),
    );
    const failure = this.takeFailure() ?? this.fileAncestorError('remove', validPath);
    if (failure !== undefined) return Err(failure);
    if (validPath === '/') return Err(new PortError('vfs', 'unsupported', 'remove', 'The VFS root cannot be removed'));
    const node = this.nodes.get(validPath);
    if (node === undefined) return Err(new PortError('vfs', 'not-found', 'remove', `Path not found: ${validPath}`));
    const prefix = `${validPath}/`;
    const descendants = [...this.nodes.keys()].filter(candidate => candidate.startsWith(prefix));
    if (node.kind === 'directory' && descendants.length > 0 && !normalizedOptions.recursive) {
      return Err(new PortError('vfs', 'directory-not-empty', 'remove', `Directory is not empty: ${validPath}`));
    }
    for (const descendant of descendants) this.nodes.delete(descendant);
    this.nodes.delete(validPath);
    return Ok(undefined);
  }

  private takeFailure(): VfsError | undefined {
    const failure = this.nextFailure;
    this.nextFailure = undefined;
    return failure;
  }

  private fileAncestorError(operation: string, path: string): VfsError | undefined {
    const file = InMemoryVirtualFileSystem.ancestors(path).find(ancestor => this.nodes.get(ancestor)?.kind === 'file');
    return file === undefined
      ? undefined
      : new PortError('vfs', 'not-a-directory', operation, `Ancestor is not a directory: ${file}`, { ancestor: file });
  }

  assertCalls(expected: readonly VfsCall[]): void {
    this.snapshot.assertEqual('VFS calls', this.calls, expected);
  }

  assertFiles(expected: Readonly<Record<string, Uint8Array>>): void {
    this.snapshot.assertEqual('VFS files', this.files, expected);
  }

  private static parentPath(path: string): string {
    const index = path.lastIndexOf('/');
    return index === 0 ? '/' : path.slice(0, index);
  }

  private static ancestors(path: string): readonly string[] {
    const segments = path.split('/').filter(Boolean);
    return segments.slice(0, -1).map((_, index) => `/${segments.slice(0, index + 1).join('/')}`);
  }
}

class InMemoryTerminal implements Terminal {
  private readonly input: (string | null)[];
  private readonly recordedCalls: TerminalCall[] = [];
  private readonly snapshot = new Snapshot();
  private closed = false;
  private nextFailure: TerminalError | undefined;
  private sequence = 0;

  constructor(
    input: readonly (string | null)[] = [],
    readonly interactive = false,
    private readonly policy: TerminalPolicy = new TerminalPolicy(),
  ) {
    if (!Array.isArray(input)) {
      throw new TypeError('In-memory terminal input must be an array');
    }
    if (typeof interactive !== 'boolean') {
      throw new TypeError('In-memory terminal interactive must be a boolean');
    }
    for (const line of input) InMemoryTerminal.assertLine(line);
    this.input = [...input];
  }

  get calls(): readonly TerminalCall[] {
    return this.recordedCalls.map(call =>
      call.method === 'write'
        ? Object.freeze({ ...call, output: Object.freeze({ ...call.output }) })
        : Object.freeze({ ...call, input: Object.freeze({ ...call.input }) }),
    );
  }

  close(): void {
    this.closed = true;
  }

  enqueue(line: string | null): void {
    InMemoryTerminal.assertLine(line);
    this.input.push(line);
  }

  failNext(error: TerminalError): void {
    this.nextFailure = error;
  }

  write(output: TerminalWrite): Result<void, TerminalError> {
    const checked = this.policy.checkWrite(output);
    if (!checked.ok) return Err(checked.error);
    const validated = checked.value;
    this.recordedCalls.push(Object.freeze({ method: 'write', output: validated, sequence: this.sequence++ }));
    if (this.closed) return Err(new PortError('terminal', 'closed', 'write', 'Terminal is closed'));
    const failure = this.nextFailure;
    this.nextFailure = undefined;
    return failure === undefined ? Ok(undefined) : Err(failure);
  }

  readLine(input: TerminalRead = {}): Result<string | null, TerminalError> {
    const checked = this.policy.checkRead(input);
    if (!checked.ok) return Err(checked.error);
    const validated = checked.value;
    this.recordedCalls.push(Object.freeze({ input: validated, method: 'readLine', sequence: this.sequence++ }));
    if (this.closed) return Err(new PortError('terminal', 'closed', 'readLine', 'Terminal is closed'));
    const failure = this.nextFailure;
    this.nextFailure = undefined;
    if (failure !== undefined) return Err(failure);
    return Ok(this.input.shift() ?? null);
  }

  assertCalls(expected: readonly TerminalCall[]): void {
    this.snapshot.assertEqual('Terminal calls', this.calls, expected);
  }

  private static assertLine(line: unknown): asserts line is string | null {
    if (line !== null && typeof line !== 'string') {
      throw new TypeError('In-memory terminal input must contain only strings or null');
    }
  }
}

class InMemoryLoggerSink implements LoggerSink {
  private readonly recordedCalls: LoggerCall[] = [];
  private readonly recordedRecords: Readonly<LogRecord>[] = [];
  private readonly snapshot = new Snapshot();
  private nextFailure: LoggingError | undefined;
  private sequence = 0;

  constructor(private readonly policy: LoggingPolicy = new LoggingPolicy()) {}

  get calls(): readonly LoggerCall[] {
    return this.recordedCalls.map(call =>
      call.method === 'emit'
        ? Object.freeze({ ...call, record: InMemoryLoggerSink.cloneRecord(call.record) })
        : Object.freeze({ ...call }),
    );
  }

  get records(): readonly Readonly<LogRecord>[] {
    return this.recordedRecords.map(record => InMemoryLoggerSink.cloneRecord(record));
  }

  failNext(error: LoggingError): void {
    this.nextFailure = error;
  }

  emit(record: LogRecord): Result<void, LoggingError> {
    const checked = this.policy.checkRecord(record);
    if (!checked.ok) return Err(checked.error);
    const snapshot = InMemoryLoggerSink.cloneRecord(checked.value);
    this.recordedCalls.push(Object.freeze({ method: 'emit', record: snapshot, sequence: this.sequence++ }));
    const failure = this.nextFailure;
    this.nextFailure = undefined;
    if (failure !== undefined) return Err(failure);
    this.recordedRecords.push(snapshot);
    return Ok(undefined);
  }

  flush(): Result<void, LoggingError> {
    this.recordedCalls.push(Object.freeze({ method: 'flush', sequence: this.sequence++ }));
    const failure = this.nextFailure;
    this.nextFailure = undefined;
    return failure === undefined ? Ok(undefined) : Err(failure);
  }

  assertCalls(expected: readonly LoggerCall[]): void {
    this.snapshot.assertEqual('Logger calls', this.calls, expected);
  }

  assertRecords(expected: readonly LogRecord[]): void {
    this.snapshot.assertEqual('Log records', this.records, expected);
  }

  private static cloneRecord(record: Readonly<LogRecord>): Readonly<LogRecord> {
    return Object.freeze({
      ...record,
      ...(record.attributes === undefined ? {} : { attributes: Object.freeze({ ...record.attributes }) }),
    });
  }
}

class InMemoryMetricsCollector implements MetricsCollector {
  private readonly recordedCalls: MetricsCall[] = [];
  private readonly recordedMetrics: Readonly<MetricRecord>[] = [];
  private readonly snapshot = new Snapshot();
  private nextFailure: MetricsError | undefined;
  private sequence = 0;

  constructor(private readonly policy: MetricsPolicy = new MetricsPolicy()) {}

  get calls(): readonly MetricsCall[] {
    return this.recordedCalls.map(call =>
      call.method === 'record'
        ? Object.freeze({ ...call, metric: InMemoryMetricsCollector.cloneRecord(call.metric) })
        : Object.freeze({ ...call }),
    );
  }

  get metrics(): readonly Readonly<MetricRecord>[] {
    return this.recordedMetrics.map(metric => InMemoryMetricsCollector.cloneRecord(metric));
  }

  failNext(error: MetricsError): void {
    this.nextFailure = error;
  }

  record(metric: MetricRecord): Result<void, MetricsError> {
    const checked = this.policy.checkRecord(metric);
    if (!checked.ok) return Err(checked.error);
    const snapshot = InMemoryMetricsCollector.cloneRecord(checked.value);
    this.recordedCalls.push(Object.freeze({ method: 'record', metric: snapshot, sequence: this.sequence++ }));
    const failure = this.nextFailure;
    this.nextFailure = undefined;
    if (failure !== undefined) return Err(failure);
    this.recordedMetrics.push(snapshot);
    return Ok(undefined);
  }

  flush(): Result<void, MetricsError> {
    this.recordedCalls.push(Object.freeze({ method: 'flush', sequence: this.sequence++ }));
    const failure = this.nextFailure;
    this.nextFailure = undefined;
    return failure === undefined ? Ok(undefined) : Err(failure);
  }

  assertCalls(expected: readonly MetricsCall[]): void {
    this.snapshot.assertEqual('Metrics calls', this.calls, expected);
  }

  assertMetrics(expected: readonly MetricRecord[]): void {
    this.snapshot.assertEqual('Metric records', this.metrics, expected);
  }

  private static cloneRecord(metric: Readonly<MetricRecord>): Readonly<MetricRecord> {
    return Object.freeze({
      ...metric,
      ...(metric.attributes === undefined ? {} : { attributes: Object.freeze({ ...metric.attributes }) }),
    });
  }
}

export type { LoggerCall, MetricsCall, SystemCall, TerminalCall, VfsCall };
export {
  InMemoryLoggerSink,
  InMemoryMetricsCollector,
  InMemorySystem,
  InMemoryTerminal,
  InMemoryVirtualFileSystem,
  InterfaceAssertionError,
};
