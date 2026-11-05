import { describe, it } from 'bun:test';
import { PortError, type PortErrorDetails, portError } from '@atomicloud/diene.interfaces';
import 'should';

describe('PortError', () => {
  it('should carry the tag, name, and constructor fields', () => {
    // Arrange
    const details: PortErrorDetails = { field: 'executable', attempts: 2 };

    // Act
    const subject = portError('system', 'invalid-input', 'execute', 'boom', details);

    // Assert
    subject.should.be.instanceOf(Error);
    subject.should.be.instanceOf(PortError);
    subject._tag.should.eql('PortError');
    subject.name.should.eql('PortError');
    subject.port.should.eql('system');
    subject.code.should.eql('invalid-input');
    subject.operation.should.eql('execute');
    subject.message.should.eql('boom');
    subject.details.should.eql({ field: 'executable', attempts: 2 });
  });

  it('should keep the message it was given', () => {
    // Arrange
    const expected = 'disk full';

    // Act
    const actual = portError('vfs', 'io', 'writeFile', expected).message;

    // Assert
    actual.should.equal(expected);
  });

  it('should freeze a defensive copy of the details record', () => {
    // Arrange
    const source: Record<string, unknown> = { field: 'name' };

    // Act
    const subject = portError('metrics', 'io', 'record', 'msg', source);
    source.field = 'mutated';

    // Assert
    Object.isFrozen(subject.details).should.be.true();
    subject.details.should.eql({ field: 'name' });
  });

  it('should default details to an empty frozen record when omitted', () => {
    // Act
    const subject = portError('vfs', 'not-found', 'readFile', 'missing');

    // Assert
    Object.isFrozen(subject.details).should.be.true();
    subject.details.should.eql({});
  });

  it('should construct directly with the same identity as the factory', () => {
    // Act
    const direct = new PortError('terminal', 'closed', 'write', 'closed stream');

    // Assert
    direct.should.be.instanceOf(PortError);
    (direct instanceof PortError).should.be.true();
    direct.port.should.eql('terminal');
    direct.details.should.eql({});
  });
});

describe('PortError subclasses', () => {
  class FsError extends PortError<'vfs'> {}

  it('should not treat a plain PortError as a subclass instance', () => {
    // Arrange
    const plain = portError('vfs', 'io', 'readFile', 'disk fault');

    // Act
    const actual = plain instanceof FsError;

    // Assert
    actual.should.be.false();
  });

  it('should treat a subclass instance as both the subclass and the base', () => {
    // Arrange
    const subject = new FsError('vfs', 'io', 'readFile', 'disk fault');

    // Act
    const asSubclass = subject instanceof FsError;
    const asBase = subject instanceof PortError;

    // Assert
    asSubclass.should.be.true();
    asBase.should.be.true();
  });

  it('should still accept a branded value from another copy of the package on the base', () => {
    // Arrange
    const crossCopy = Object.defineProperty({}, Symbol.for('AtomiCloud.Diene.Interfaces.PortError'), {
      value: true,
    });

    // Act
    const asBase = crossCopy instanceof PortError;
    const asSubclass = crossCopy instanceof FsError;

    // Assert
    asBase.should.be.true();
    asSubclass.should.be.false();
  });
});
