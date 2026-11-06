import { describe, it } from 'bun:test';
import { assertLogRecords, assertMetricRecords } from '@atomicloud/diene.interfaces/test-helper';
import 'should';
import { appIdentitySchema } from '../../src/lib/resource';
import {
  AppIdentityBuilder,
  DEFAULT_IDENTITY,
  OtelAssertions,
  OtelBlockFixtures,
  OtelTestHarness,
} from '../../src/test-helper';

describe('AppIdentityBuilder', () => {
  it('should build a valid default identity and override single fields immutably', () => {
    // Arrange
    const base = new AppIdentityBuilder();

    // Act
    const changed = base.with({ landscape: 'tauros' });

    // Assert
    appIdentitySchema.safeParse(base.build()).success.should.be.true();
    base.build().should.eql(DEFAULT_IDENTITY);
    changed.build().should.eql({ ...DEFAULT_IDENTITY, landscape: 'tauros' });
    changed.attributes()['deployment.environment.name']?.should.eql('tauros');
    changed.attributes()['atomi.landscape']?.should.eql('tauros');
  });
});

describe('OtelTestHarness', () => {
  it('should start the runtime on the shared mocks and capture every signal', async () => {
    // Arrange
    const harness = new OtelTestHarness();
    const run = harness.start(new OtelBlockFixtures().otlp());

    // Act
    await run.runtime.loggerSink.emit({ level: 'info', message: 'hi' }).unwrap();
    await run.runtime.metricsCollector.record({ kind: 'gauge', name: 'depth', value: 4 }).unwrap();
    await run.runtime.traceEmitter.emit({ name: 'work' }).unwrap();
    await run.runtime.shutdown();

    // Assert
    assertLogRecords(run.logger, [{ level: 'info', message: 'hi' }]);
    assertMetricRecords(run.metrics, [{ kind: 'gauge', name: 'depth', value: 4 }]);
    run.traces.records.should.eql([{ name: 'work' }]);
    new OtelAssertions().identityResource(run.runtime.resourceAttributes, DEFAULT_IDENTITY);
    run.runtime.active.should.eql({ logs: false, metrics: false, traces: false });
  });

  it('should honour the identity and environment it is given', () => {
    // Arrange
    const identity = new AppIdentityBuilder().with({ service: 'billing' }).build();

    // Act
    const run = new OtelTestHarness().start(new OtelBlockFixtures().canonical(), identity, {
      OTEL_RESOURCE_ATTRIBUTES: 'team=core',
    });

    // Assert
    run.runtime.resourceAttributes['service.name']?.should.eql('billing');
    run.runtime.resourceAttributes.team?.should.eql('core');
  });
});
