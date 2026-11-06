---
name: diene-interfaces-usage
description: Use when consuming @atomicloud/diene.interfaces — importing the effect-port contracts, wiring an adapter, or faking a port in tests with the test-helper subpath.
---

`@atomicloud/diene.interfaces` ships the TypeScript family's shared effect-port
contracts as dual **ESM + CJS** with bundled types. It owns exactly five ports —
**System**, **VirtualFileSystem**, **Terminal**, **LoggerSink**, and
**MetricsCollector** — plus framework-free in-memory doubles for them. It ships no
concrete adapter.

- **Contracts** import from the package root; both `import` and `require` resolve,
  and TypeScript picks up `.d.ts` (ESM) or `.d.cts` (CJS) automatically.
- **Test doubles** (in-memory mocks with assertion methods) import from the
  `@atomicloud/diene.interfaces/test-helper` subpath and depend on no test framework.

The root exports the `System`, `VirtualFileSystem`, `Terminal`, `LoggerSink`, and
`MetricsCollector` contracts and a stateless validation policy class per port
(`SystemPolicy`, `VfsPolicy`, `TerminalPolicy`, `LoggingPolicy`, `MetricsPolicy`,
`TelemetryPolicy`). The helper subpath exports the matching
`InMemorySystem`, `InMemoryVirtualFileSystem`, `InMemoryTerminal`,
`InMemoryLoggerSink`, and `InMemoryMetricsCollector` doubles; each takes its policy
by constructor injection and carries ordered-call and captured-value assertion
methods (`assertCalls`, `assertFiles`, `assertRecords`, `assertMetrics`).

Every fallible port method returns the published `@atomicloud/diene.result`
`Result` directly — ports never throw for normal control flow, so branch on the
returned value instead of using `try`/`catch`.

**Tracing is not here.** Trace/span contracts and their test doubles are owned by
the OTel package; `LoggerSink` and `MetricsCollector` are plain effect
seams that OTel composes with.

Read [patterns.md](patterns.md) for the do's, don'ts, a wiring and test example,
and the control API of each test-helper double. Read the interfaces standard for
the full ownership, Result-failure, and adapters-vs-contracts-vs-OTel boundary.
