# Testing telemetry

Import the logger and metrics mocks from `@atomicloud/diene.interfaces/test-helper`
and everything OTel-specific from `@atomicloud/diene.otel/test-helper`. No
collector, no network.

```ts
import { assertLogRecords, assertMetricRecords } from '@atomicloud/diene.interfaces/test-helper';
import {
  AppIdentityBuilder,
  OtelAssertions,
  OtelBlockFixtures,
  OtelTestHarness,
} from '@atomicloud/diene.otel/test-helper';

// Init with InMemoryLoggerSink, InMemoryMetricsCollector and InMemoryTraceEmitter injected.
const run = new OtelTestHarness().start(
  new OtelBlockFixtures().otlp(),
  new AppIdentityBuilder().with({ service: 'billing' }).build(),
);

await serviceUnderTest(run.runtime);

assertLogRecords(run.logger, [{ level: 'info', message: 'charged' }]);
assertMetricRecords(run.metrics, [{ kind: 'counter', name: 'charges', value: 1 }]);
const otel = new OtelAssertions();
otel.traceRecords(run.traces, [{ name: 'charge', status: 'ok' }]);
otel.identityResource(run.runtime.resourceAttributes, new AppIdentityBuilder().with({ service: 'billing' }).build());
await run.runtime.shutdown();
```

To inject the mocks into your own init call, pass them as seams:

```ts
new OtelBootstrap().init(block, identity, { environment: {}, seams: { logger, metrics, traces } });
```

`OtelBlockFixtures` gives `canonical()`, `disabled()`, `console()` and `otlp()` blocks.
`OtelAssertions` throws `OtelAssertionError` with expected and actual on a mismatch.
`InMemoryTraceEmitter.failNext(new TraceError('io', 'emit', 'down'))` fails the next call.
