import { describe, it } from 'bun:test';
import {
  type Checked,
  type MetricKind,
  type MetricRecord,
  MetricsPolicy,
  PortError,
  type TelemetryAttributes,
  TelemetryPolicy,
} from '@atomicloud/diene.interfaces';
import 'should';
import { expectErr, expectOk } from './support/result.js';

const policy = new MetricsPolicy();

describe('MetricsPolicy.validateRecord', () => {
  it.each<MetricKind>([
    'counter',
    'gauge',
    'histogram',
  ])('should accept a valid %s metric and freeze it', async kind => {
    // Act
    const actual = await expectOk(policy.validateRecord({ kind, name: 'http.requests', value: 3 }));

    // Assert
    actual.kind.should.eql(kind);
    actual.name.should.eql('http.requests');
    actual.value.should.eql(3);
    Object.hasOwn(actual, 'attributes').should.be.false();
    Object.isFrozen(actual).should.be.true();
  });

  it('should retain a valid unit and sorted attributes', async () => {
    // Act
    const actual = await expectOk(
      policy.validateRecord({
        kind: 'histogram',
        name: 'latency',
        value: 12.5,
        unit: 'ms',
        attributes: { z: 1, a: 2 },
      }),
    );

    // Assert
    (actual.unit ?? '').should.eql('ms');
    Object.keys(actual.attributes ?? {}).should.eql(['a', 'z']);
  });

  it('should omit the unit key entirely when unit is undefined', async () => {
    // Act
    const actual = await expectOk(policy.validateRecord({ kind: 'gauge', name: 'temp', value: -4 }));

    // Assert
    Object.hasOwn(actual, 'unit').should.be.false();
    actual.value.should.eql(-4);
  });

  it.each<MetricKind>(['counter', 'histogram'])('should allow zero but reject a negative %s', async kind => {
    // Act
    const zero = await expectOk(policy.validateRecord({ kind, name: 'hits', value: 0 }));
    const error = await expectErr(policy.validateRecord({ kind, name: 'hits', value: -1 }));

    // Assert
    zero.value.should.eql(0);
    error.details.should.eql({ field: 'value' });
    error.message.should.match(/must not be negative/);
  });

  it.each([
    ['null', null as unknown as MetricRecord],
    ['a primitive', 9 as unknown as MetricRecord],
  ])('should reject a non-object metric (%s)', async (_label, metric) => {
    // Act
    const error = await expectErr(policy.validateRecord(metric));

    // Assert
    error.port.should.eql('metrics');
    error.operation.should.eql('record');
    error.details.should.eql({ field: 'metric' });
  });

  it('should reject an invalid kind', async () => {
    // Act
    const error = await expectErr(
      policy.validateRecord({ kind: 'summary' as unknown as MetricKind, name: 'x', value: 1 }),
    );

    // Assert
    error.details.should.eql({ field: 'kind' });
  });

  it.each([
    ['non-string', 5 as unknown as string],
    ['empty', ''],
    ['leading digit', '1bad'],
    ['illegal char', 'has space'],
  ])('should reject an invalid instrument name (%s)', async (_label, name) => {
    // Act
    const error = await expectErr(policy.validateRecord({ kind: 'counter', name, value: 1 }));

    // Assert
    error.details.should.eql({ field: 'name' });
  });

  it.each([
    ['non-number', '1' as unknown as number],
    ['NaN', Number.NaN],
    ['Infinity', Number.POSITIVE_INFINITY],
  ])('should reject a non-finite value (%s)', async (_label, value) => {
    // Act
    const error = await expectErr(policy.validateRecord({ kind: 'gauge', name: 'x', value }));

    // Assert
    error.details.should.eql({ field: 'value' });
    error.message.should.match(/must be finite/);
  });

  it.each([
    ['non-string', 5 as unknown as string],
    ['blank', '   '],
  ])('should reject an invalid unit (%s)', async (_label, unit) => {
    // Act
    const error = await expectErr(policy.validateRecord({ kind: 'gauge', name: 'x', value: 1, unit }));

    // Assert
    error.details.should.eql({ field: 'unit' });
  });

  it('should propagate telemetry validation failure for bad attributes', async () => {
    // Act
    const error = await expectErr(
      policy.validateRecord({
        kind: 'counter',
        name: 'x',
        value: 1,
        attributes: { '': 1 },
      }),
    );

    // Assert
    error.port.should.eql('metrics');
    error.message.should.match(/name/i);
  });
});

describe('MetricsPolicy telemetry injection', () => {
  it('should delegate attribute checks to the injected telemetry policy', async () => {
    // Arrange
    class RejectingTelemetry extends TelemetryPolicy {
      override checkAttributes<P extends 'logging' | 'metrics'>(
        _attributes: TelemetryAttributes | undefined,
        port: P,
        operation: string,
      ): Checked<TelemetryAttributes | undefined, PortError<P>> {
        return { error: new PortError(port, 'invalid-input', operation, 'injected'), ok: false };
      }
    }
    const subject = new MetricsPolicy(new RejectingTelemetry());

    // Act
    const error = await expectErr(subject.validateRecord({ kind: 'gauge', name: 'temp', value: 1 }));

    // Assert
    error.message.should.eql('injected');
    error.port.should.eql('metrics');
  });
});
