import type { Result } from '@atomicloud/diene.result';
import { PortError, type TerminalError } from './error.js';
import { type Checked, PortPolicy } from './validation.js';

type TerminalChannel = 'stderr' | 'stdout';

interface TerminalWrite {
  readonly channel: TerminalChannel;
  readonly text: string;
  readonly newline?: boolean;
}

interface TerminalRead {
  readonly prompt?: string;
}

interface Terminal {
  readonly interactive: boolean;
  write(output: TerminalWrite): Result<void, TerminalError>;
  readLine(input?: TerminalRead): Result<string | null, TerminalError>;
}

class TerminalPolicy extends PortPolicy {
  // biome-ignore lint/complexity/noUselessConstructor: Bun counts an implicit constructor as an uncovered function
  constructor() {
    super();
  }

  checkWrite(output: TerminalWrite): Checked<Required<TerminalWrite>, TerminalError> {
    if (typeof output !== 'object' || output === null) {
      return this.invalid('write', 'output', 'Terminal output must be an object');
    }
    if (output.channel !== 'stdout' && output.channel !== 'stderr') {
      return this.invalid('write', 'channel', 'Terminal channel must be stdout or stderr');
    }
    if (typeof output.text !== 'string') {
      return this.invalid('write', 'text', 'Terminal text must be a string');
    }
    if (output.newline !== undefined && typeof output.newline !== 'boolean') {
      return this.invalid('write', 'newline', 'Terminal newline must be a boolean');
    }
    return this.accept(Object.freeze({ channel: output.channel, text: output.text, newline: output.newline ?? false }));
  }

  checkRead(input: TerminalRead = {}): Checked<Readonly<TerminalRead>, TerminalError> {
    if (
      typeof input !== 'object' ||
      input === null ||
      Array.isArray(input) ||
      ![Object.prototype, null].includes(Object.getPrototypeOf(input))
    ) {
      return this.invalid('readLine', 'input', 'Terminal input must be an object');
    }
    if (input.prompt !== undefined && typeof input.prompt !== 'string') {
      return this.invalid('readLine', 'prompt', 'Terminal prompt must be a string');
    }
    return this.accept(Object.freeze(input.prompt === undefined ? {} : { prompt: input.prompt }));
  }

  validateWrite(output: TerminalWrite): Result<Required<TerminalWrite>, TerminalError> {
    return this.toResult(this.checkWrite(output));
  }

  validateRead(input: TerminalRead = {}): Result<Readonly<TerminalRead>, TerminalError> {
    return this.toResult(this.checkRead(input));
  }

  private invalid(operation: string, field: string, message: string): Checked<never, TerminalError> {
    return this.reject(new PortError('terminal', 'invalid-input', operation, message, { field }));
  }
}

export type { Terminal, TerminalChannel, TerminalRead, TerminalWrite };
export { TerminalPolicy };
