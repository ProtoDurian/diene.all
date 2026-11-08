import { describe, it } from 'bun:test';
import {
  type Checked,
  type LogLevel,
  LoggingPolicy,
  type LogRecord,
  PortError,
  type TelemetryAttributes,
  TelemetryPolicy,
} from '@atomicloud/diene.interfaces';
import 'should';
import { expectErr, expectOk } from './support/result.js';

const policy = new LoggingPolicy();

describe('LoggingPolicy.validateRecord', () => {
  it.each<LogLevel>([
    'trace',
    'debug',
    'info',
    'warn',
    'error',
    'fatal',
  ])('should accept the %s level and freeze the normalized record', async level => {
    // Act
    const actual = await expectOk(policy.validateRecord({ level, message: 'hello' }));

    // Assert
    actual.level.should.eql(level);
    actual.message.should.eql('hello');
    Object.hasOwn(actual, 'attributes').should.be.false();
    Object.isFrozen(actual).should.be.true();
  });

  it('should normalize and sort provided attributes', async () => {
    // Act
    const actual = await expectOk(policy.validateRecord({ level: 'info', message: 'm', attributes: { b: 2, a: 1 } }));

    // Assert
    Object.keys(actual.attributes ?? {}).should.eql(['a', 'b']);
    Object.isFrozen(actual.attributes).should.be.true();
  });

  it.each([
    ['null', null as unknown as LogRecord],
    ['a primitive', 7 as unknown as LogRecord],
  ])('should reject a non-object record (%s)', async (_label, record) => {
    // Act
    const error = await expectErr(policy.validateRecord(record));

    // Assert
    error.port.should.eql('logging');
    error.operation.should.eql('emit');
    error.message.should.match(/must be an object/);
  });

  it('should reject an invalid level with the level field', async () => {
    // Act
    const error = await expectErr(policy.validateRecord({ level: 'critical' as unknown as LogLevel, message: 'm' }));

    // Assert
    error.message.should.match(/Log level is invalid/);
    error.details.should.eql({ field: 'level' });
  });

  it.each([
    ['non-string', 5 as unknown as string],
    ['blank', '   '],
    ['empty', ''],
  ])('should reject a blank message (%s)', async (_label, message) => {
    // Act
    const error = await expectErr(policy.validateRecord({ level: 'info', message }));

    // Assert
    error.message.should.match(/must not be blank/);
    error.details.should.eql({ field: 'message' });
  });

  it('should propagate telemetry validation failure for bad attributes', async () => {
    // Act
    const error = await expectErr(
      policy.validateRecord({
        level: 'warn',
        message: 'm',
        attributes: { a: {} as unknown as number },
      }),
    );

    // Assert
    error.port.should.eql('logging');
    error.operation.should.eql('emit');
    error.message.should.match(/finite primitives/);
  });
});

describe('LoggingPolicy telemetry injection', () => {
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
    const subject = new LoggingPolicy(new RejectingTelemetry());

    // Act
    const error = await expectErr(subject.validateRecord({ level: 'info', message: 'm' }));

    // Assert
    error.message.should.eql('injected');
    error.port.should.eql('logging');
  });
});
