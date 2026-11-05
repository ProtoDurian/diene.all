# @atomicloud/diene.interfaces — patterns

## Do

- Import the port **types** from the package root
  (`@atomicloud/diene.interfaces`); let the exports map pick the right module and
  declaration file for your module system.
- Depend on the **contract**, not a concrete implementation. Accept a port
  (System, VirtualFileSystem, Terminal, LoggerSink, or MetricsCollector) as a
  constructor dependency and let the caller inject the adapter.
- Branch on the returned `Result`. Fallible methods return the published
  `@atomicloud/diene.result` value directly; `map`/`match` the typed error at the
  boundary and propagate it rather than throwing.
- Treat a non-zero process exit from **System** as an ordinary result value — the
  error branch is for the port failing to do its job, not for a command reporting
  its own failure.
- Get trace-aware logging from the **OTel package** when you need it. It layers on
  top of these seams; it is not a second logging contract.

## Don't

- Don't deep-import into `dist/` internals; only the root entry and the
  `test-helper` subpath are public.
- Don't rely on side effects at import time — the package is `sideEffects: false`.
- Don't re-derive a port's invariants in your own adapter. Reuse the package's
  shared validation so your adapter rejects exactly what the mock rejects.
- Don't look for tracing or span contracts here — they live in the OTel package
  (RB-19).
- Don't wrap port calls in `try`/`catch` for normal control flow; ports do not
  throw.

## Test doubles

In-memory mocks and assertions ship on the subpath
`@atomicloud/diene.interfaces/test-helper` and carry **no** test-framework
dependency, so any runner can use them.

- Import a fake System, VirtualFileSystem, Terminal, LoggerSink, or
  MetricsCollector from the subpath instead of hand-rolling one — the shipped
  double already tracks the real contract, records interactions deterministically,
  and enforces the same invariants (it rejects what a real port rejects).
- Use the shipped assertions to check what a port was asked to do; they fail with
  a precise message and otherwise pass.
- Trace and vendor/SDK-specific telemetry doubles are **not** here — the OTel
  TestHelper owns those.

The concrete contract names are `System`, `VirtualFileSystem`, `Terminal`,
`LoggerSink`, and `MetricsCollector`. Their matching doubles are prefixed with
`InMemory` and live only on `/test-helper`; root remains the production entry.

## Example

A service takes the port in its constructor:

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

A test injects the in-memory double, fails one call, and checks the calls:

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

## Double API

| Double                      | Control                                                                       | Inspection         | Assertion methods              |
| --------------------------- | ----------------------------------------------------------------------------- | ------------------ | ------------------------------ |
| `InMemorySystem`            | outcomes in the constructor, `enqueue(outcome)`                               | `calls`            | `assertCalls`                  |
| `InMemoryVirtualFileSystem` | `failNext(error)`                                                             | `calls`, `files`   | `assertCalls`, `assertFiles`   |
| `InMemoryTerminal`          | input lines in the constructor, `enqueue(line)`, `failNext(error)`, `close()` | `calls`            | `assertCalls`                  |
| `InMemoryLoggerSink`        | `failNext(error)`                                                             | `calls`, `records` | `assertCalls`, `assertRecords` |
| `InMemoryMetricsCollector`  | `failNext(error)`                                                             | `calls`, `metrics` | `assertCalls`, `assertMetrics` |

- `failNext` fails the next call only.
- `InMemorySystem` returns `unexpected-call` when no outcome is queued.
- Every recorded call has a `sequence`, starting at `0` per double. Put it in the
  calls you expect.
- A failed assertion throws `InterfaceAssertionError` with `label`, `expected` and
  `actual`.

## Shared validation

Adapters reuse the package's rules through its stateless policy classes:
`SystemPolicy`, `VfsPolicy`, `TerminalPolicy`, `LoggingPolicy`, `MetricsPolicy` and
`TelemetryPolicy`. Each rule is a method pair. `validate*` returns a `Result`.
`check*` returns `Checked` (`{ ok, value }` or `{ ok, error }`) for synchronous
branching, because `Result` inspection is async. Both return the same error. Take
the policy by constructor injection, as each double does. The interfaces standard
lists every rule, the VFS failure codes, and the System timeout and signal rules.
