import { describe, it } from 'bun:test';
import {
  type TerminalChannel,
  type TerminalRead,
  type TerminalWrite,
  TerminalPolicy,
} from '@atomicloud/diene.interfaces';
import 'should';
import { expectErr, expectOk } from './support/result.js';

const policy = new TerminalPolicy();

describe('TerminalPolicy.validateWrite', () => {
  it.each([
    ['explicit true', true, true],
    ['explicit false', false, false],
    ['omitted defaults to false', undefined, false],
  ])('should normalize newline (%s)', async (_label, newline, expected) => {
    // Act
    const actual = await expectOk(policy.validateWrite({ channel: 'stdout', text: 'hi', newline } as TerminalWrite));

    // Assert
    actual.should.eql({ channel: 'stdout', text: 'hi', newline: expected });
    Object.isFrozen(actual).should.be.true();
  });

  it('should accept the stderr channel', async () => {
    // Act
    const actual = await expectOk(policy.validateWrite({ channel: 'stderr', text: '' }));

    // Assert
    actual.channel.should.eql('stderr');
  });

  it.each([
    ['null', null as unknown as TerminalWrite],
    ['a primitive', 2 as unknown as TerminalWrite],
  ])('should reject a non-object output (%s)', async (_label, output) => {
    // Act
    const error = await expectErr(policy.validateWrite(output));

    // Assert
    error.port.should.eql('terminal');
    error.operation.should.eql('write');
    error.details.should.eql({ field: 'output' });
  });

  it('should reject an invalid channel', async () => {
    // Act
    const error = await expectErr(policy.validateWrite({ channel: 'stdlog' as unknown as TerminalChannel, text: 'x' }));

    // Assert
    error.details.should.eql({ field: 'channel' });
  });

  it('should reject non-string text', async () => {
    // Act
    const error = await expectErr(policy.validateWrite({ channel: 'stdout', text: 5 as unknown as string }));

    // Assert
    error.details.should.eql({ field: 'text' });
  });

  it('should reject a non-boolean newline', async () => {
    // Act
    const error = await expectErr(
      policy.validateWrite({ channel: 'stdout', text: 'x', newline: 'yes' as unknown as boolean }),
    );

    // Assert
    error.details.should.eql({ field: 'newline' });
  });
});

describe('TerminalPolicy.validateRead', () => {
  it('should default to an empty read when called with no argument', async () => {
    // Act
    const actual = await expectOk(policy.validateRead());

    // Assert
    actual.should.eql({});
    Object.isFrozen(actual).should.be.true();
  });

  it('should retain a provided prompt', async () => {
    // Act
    const actual = await expectOk(policy.validateRead({ prompt: 'name?' }));

    // Assert
    actual.should.eql({ prompt: 'name?' });
  });

  it.each([
    ['null', null as unknown as TerminalRead],
    ['a primitive', 2 as unknown as TerminalRead],
  ])('should reject a non-object input (%s)', async (_label, input) => {
    // Act
    const error = await expectErr(policy.validateRead(input));

    // Assert
    error.operation.should.eql('readLine');
    error.details.should.eql({ field: 'input' });
  });

  it('should reject a non-string prompt', async () => {
    // Act
    const error = await expectErr(policy.validateRead({ prompt: 5 as unknown as string }));

    // Assert
    error.details.should.eql({ field: 'prompt' });
  });
});
