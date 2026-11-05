# Interfaces

The interfaces package owns the TypeScript family's shared **effect-port contracts** — the
seams that let domain and service code stay independent of the process, filesystem, terminal,
and telemetry vendors underneath it. It ships types and framework-free test doubles; it ships
no concrete adapter.

This article builds on [Three-Layer Architecture](../three-layer-architecture/index.md),
[Functional practices](../functional-practices/index.md), and
[Stateless OOP and dependency injection](../stateless-oop-di/index.md). Ports are the
dependency-inverted boundary those standards describe; failures follow the Result-based
error-handling conventions; and adapters are constructor-injected against these contracts.

---

## What this package owns

`@atomicloud/diene.interfaces` owns exactly **five** ports and nothing else:

| Port                  | Concern                                           |
| --------------------- | ------------------------------------------------- |
| **System**            | process execution                                 |
| **VirtualFileSystem** | file and directory access                         |
| **Terminal**          | terminal input and output (stdin, stdout, stderr) |
| **LoggerSink**        | structured, level-based log emission              |
| **MetricsCollector**  | counter, gauge, and histogram collection          |

Each port is a **dependency-light contract**: it names types and method shapes, carries no
vendor SDK dependency, and depends only on the published `@atomicloud/diene.result` type. The
package exposes these contracts from its root and its in-memory test doubles from the
`@atomicloud/diene.interfaces/test-helper` subpath.

The package deliberately does **not** own service configuration, wire or config semantics
(those belong to the separately owned C0 contracts standard), or any concrete adapter.

---

## Result-based failures

Every effect and every fallible port method returns the published
[`Result`](../functional-practices/index.md) value **directly**. Ports never throw and never
reject as normal control flow — a caller reasons about failure by inspecting the returned
`Result`, not by wrapping calls in `try`/`catch`.

- **Fallible operations** return a `Result` carrying a typed, port-specific error on the
  failure branch. Errors expose stable `port`, `code`, and `operation` fields so callers can
  `map`/`match` on them without parsing messages.
- **Telemetry emission is an effect and remains explicit.** Both `LoggerSink.emit` and
  `MetricsCollector.record`, as well as each sink's `flush`, return `Result<void, PortError>`.
  An adapter reports validation or transport failure through that Result; it never throws or
  silently converts a failed emission into success.
- A non-zero process exit from **System** is an ordinary result value, not an error. Reserve
  the error branch for the port failing to do its job (for example, a command that could not be
  spawned), not for the command reporting its own failure.

Because failures are values, a port and its in-memory double reach the **same** failure branch
for the same bad input. Consumers get one error model whether they run against a real adapter or
a mock.

---

## Validation and invariants

Contracts are only trustworthy if every implementation enforces the **same** invariants. The
package keeps those invariants in one place — shared, pure validation the ports and their test
doubles both call — so a mock can never silently accept input a real adapter would reject.

Invariants are expressed as the same Result the ports return: invalid input yields the failure
branch rather than a thrown exception. Representative rules the ports enforce:

- **System** — a command must be non-empty; a supplied timeout must be positive.
- **VirtualFileSystem** — a path must be non-empty; reading a missing entry, writing where a
  directory exists, or listing a file surfaces the matching typed error.
- **Terminal** — writing to or reading from a closed stream surfaces a closed-stream error.
- **MetricsCollector** — a metric has a portable kind, name, finite value, optional non-blank
  unit, and finite primitive attributes; counter values must not be negative.

The rule for anyone adding an implementation: **reuse the shared validation; never re-derive
it.** Parity between real and fake is a property of shared code, not of careful duplication.

### Result and Checked validation

The rules live on stateless policy classes, one per port module. Each rule has two methods, and
both return the same error.

- `validate*` returns a `Result`. Use it in code that already works with `Result`.
- `check*` returns `Checked`: `{ ok: true, value }` or `{ ok: false, error }`. Use it when you
  must branch synchronously, as an adapter or double does before it records a call.

`Checked` exists because `@atomicloud/diene.result` inspects a `Result` asynchronously
(`isOk()` returns a `Promise`). Each rule below is a `check*` / `validate*` pair, for example
`checkRequest` and `validateRequest`:

| Policy            | Rules                                                                             |
| ----------------- | --------------------------------------------------------------------------------- |
| `SystemPolicy`    | `Request`, `Output`                                                               |
| `VfsPolicy`       | `Path`, `Contents`, `RecursiveOptions`, `CreateDirectoryOptions`, `RemoveOptions` |
| `TerminalPolicy`  | `Write`, `Read`                                                                   |
| `LoggingPolicy`   | `Record`                                                                          |
| `MetricsPolicy`   | `Record`                                                                          |
| `TelemetryPolicy` | `Attributes` (takes the port and operation name)                                  |

`VfsPolicy` `Path` and `RecursiveOptions` take the VFS operation name, so the error names the
operation that failed. `LoggingPolicy` and `MetricsPolicy` take a `TelemetryPolicy` in their
constructor. Each double takes its policy as its last constructor argument; the default is a new
instance.

These are helpers, not port operations. Every port method still returns a `Result`.

### System semantics

- `environment` replaces the parent environment. It is not an overlay. Pass every variable the
  child needs.
- A run that takes longer than `timeoutMs` is `Err` with code `timeout`. The adapter stops
  the child.
- A child killed by a signal has no exit code. The adapter returns `Err` with code `io` and
  `details.signal` set to the signal name, for example `{ signal: 'SIGKILL' }`.
- Any exit code, zero or not, is `Ok`.

`InMemorySystem` does not run anything, so it ignores `timeoutMs`. To test the timeout path,
enqueue an `Err` with code `timeout`.

### VFS failure codes

Every VFS implementation returns these codes. The file-ancestor row is checked first.

| Operation         | Failure                                | Code                  |
| ----------------- | -------------------------------------- | --------------------- |
| any               | invalid path, contents or options      | `invalid-input`       |
| any but `exists`  | an ancestor of the path is a file      | `not-a-directory`     |
| `exists`          | the path is missing or under a file    | none: `Ok(false)`     |
| `readFile`        | the path is missing                    | `not-found`           |
| `readFile`        | the path is a directory                | `not-a-file`          |
| `writeFile`       | the path is a directory                | `not-a-file`          |
| `writeFile`       | the parent is missing                  | `not-found`           |
| `stat`            | the path is missing                    | `not-found`           |
| `list`            | the path is missing                    | `not-found`           |
| `list`            | the path is a file                     | `not-a-directory`     |
| `createDirectory` | the path is a file                     | `already-exists`      |
| `createDirectory` | the path is a directory, not recursive | `already-exists`      |
| `createDirectory` | the parent is missing, not recursive   | `not-found`           |
| `remove`          | the path is the root                   | `unsupported`         |
| `remove`          | the path is missing                    | `not-found`           |
| `remove`          | a non-empty directory, not recursive   | `directory-not-empty` |

A filesystem adapter maps `ENOENT` to `not-found`, `ENOTDIR` to `not-a-directory`, `EEXIST` to
`already-exists`, `EISDIR` to `not-a-file`, `ENOTEMPTY` to `directory-not-empty`, and `EACCES` or
`EPERM` to `permission-denied`. Anything else is `io`.

Two results are adapter-defined:

- `list` order is unspecified. Sort the entries if order matters. The double sorts by name.
- `stat(...).size` of a directory is adapter-defined. The double reports `0`.

---

## Adapters vs contracts vs OTel

Three layers, three owners — keep them separate:

- **Contracts (this package).** Types and invariants only. No vendor SDK, no I/O, no telemetry
  exporter. Domain and service code depend here and nowhere lower.
- **Adapters (elsewhere).** Concrete implementations of these contracts against a real vendor
  or runtime (a real filesystem, a real process spawner, a real metrics registry). They live in
  their own packages, are wired in by dependency injection, and never leak their vendor back
  through the contract type.
- **OTel (the separate OTel package).** **Tracing is not owned here.** Per RB-19, trace and
  span contracts, their in-memory doubles, and any vendor- or SDK-specific telemetry assertions
  are language-local to the OTel package. `LoggerSink` and `MetricsCollector` here are plain
  effect seams; trace-context propagation and span emission belong to OTel, which composes with
  these ports rather than replacing them.

If a contract would force a decision about a specific vendor, exporter, or wire format, it does
not belong in this package.

---

## Wiring

Consumers depend on the **contract**, receive a concrete implementation by injection, and stay
oblivious to which one they got:

- Import the port **types** from the package root.
- Accept a port as a constructor dependency; never construct a concrete adapter inside domain
  or service code.
- Branch on the returned `Result` at the boundary; propagate or `map` the typed error rather
  than throwing.
- Obtain trace-aware logging from the OTel package when you need it — it layers on top of these
  seams; it is not a second logging contract.

A service takes the port in its constructor and returns the port's `Result`:

```ts
import type { VfsError, VirtualFileSystem } from '@atomicloud/diene.interfaces';
import type { Result } from '@atomicloud/diene.result';

class ReportStore {
  constructor(private readonly vfs: VirtualFileSystem) {}

  save(name: string, body: string): Result<void, VfsError> {
    return this.vfs.writeFile(`/reports/${name}`, new TextEncoder().encode(body));
  }
}
```

The published package installs `@atomicloud/diene.result` as a runtime dependency, so the
`Result` type resolves for both ESM and CommonJS consumers without extra setup.

---

## Test-helper use

Framework-free in-memory doubles and assertions ship at
`@atomicloud/diene.interfaces/test-helper`. They carry **no** dependency on any test framework,
so any runner can use them.

- **Mocks** implement the real contracts, record validated interactions deterministically
  (including operational failures), and enforce the same invariants as real adapters — they
  reject malformed input before it can mutate fake state.
- **Assertions** are plain functions that fail with a precise message and otherwise pass;
  they read the recorded interactions to check what a port was asked to do.
- **Parity and assert-the-asserter.** The package's own tests prove each shipped assertion both
  fails on a known-bad interaction and passes on a known-good one, and run a shared contract
  suite so a mock and any dependency-free reference implementation agree on the same inputs.

Interfaces owns the doubles for its five ports. **Trace and vendor/SDK-specific telemetry test
helpers live in the OTel package**, consistent with the boundary above. When you need a fake
`System`, `VirtualFileSystem`, `Terminal`, `LoggerSink`, or `MetricsCollector` in a consumer
test, import it from the test-helper subpath instead of hand-rolling one — the shipped double
already tracks the real contract.

### Controlling and inspecting a double

| Double                      | Control                                                                       | Inspection         | Assertion methods              |
| --------------------------- | ----------------------------------------------------------------------------- | ------------------ | ------------------------------ |
| `InMemorySystem`            | outcomes in the constructor, `enqueue(outcome)`                               | `calls`            | `assertCalls`                  |
| `InMemoryVirtualFileSystem` | `failNext(error)`                                                             | `calls`, `files`   | `assertCalls`, `assertFiles`   |
| `InMemoryTerminal`          | input lines in the constructor, `enqueue(line)`, `failNext(error)`, `close()` | `calls`            | `assertCalls`                  |
| `InMemoryLoggerSink`        | `failNext(error)`                                                             | `calls`, `records` | `assertCalls`, `assertRecords` |
| `InMemoryMetricsCollector`  | `failNext(error)`                                                             | `calls`, `metrics` | `assertCalls`, `assertMetrics` |

- `failNext` fails the next call only. A second `failNext` replaces the first.
- `InMemorySystem` returns `unexpected-call` when no outcome is queued.
- Each recorded call has a `sequence` number. It starts at `0` for each double. Put it in the
  calls you expect.
- An assertion throws `InterfaceAssertionError` on a mismatch. The error has `label`,
  `expected` and `actual` fields.

A test for the `ReportStore` above:

```ts
import { PortError } from '@atomicloud/diene.interfaces';
import { InMemoryVirtualFileSystem } from '@atomicloud/diene.interfaces/test-helper';

it('should surface a disk fault from the store', async () => {
  // Arrange
  const vfs = new InMemoryVirtualFileSystem();
  vfs.createDirectory('/reports');
  vfs.failNext(new PortError('vfs', 'io', 'writeFile', 'disk full'));
  const store = new ReportStore(vfs);

  // Act
  const error = await store.save('a.txt', 'hi').unwrapErr();

  // Assert
  error.code.should.equal('io');
  vfs.assertCalls([
    { method: 'createDirectory', options: { recursive: false }, path: '/reports', sequence: 0 },
    { contents: new TextEncoder().encode('hi'), method: 'writeFile', path: '/reports/a.txt', sequence: 1 },
  ]);
});
```
