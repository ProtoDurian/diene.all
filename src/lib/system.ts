import type { Result } from '@atomicloud/diene.result';
import { PortError, type SystemError } from './error.js';
import { type Checked, PortPolicy } from './validation.js';

interface ProcessRequest {
  readonly executable: string;
  readonly arguments?: readonly string[];
  readonly cwd?: string;
  readonly environment?: Readonly<Record<string, string>>;
  readonly stdin?: string;
  readonly timeoutMs?: number;
}

interface ProcessOutput {
  readonly exitCode: number;
  readonly stdout: string;
  readonly stderr: string;
}

interface System {
  execute(request: ProcessRequest): Result<ProcessOutput, SystemError>;
}

class SystemPolicy extends PortPolicy {
  // biome-ignore lint/complexity/noUselessConstructor: Bun counts an implicit constructor as an uncovered function
  constructor() {
    super();
  }

  checkRequest(request: ProcessRequest): Checked<ProcessRequest, SystemError> {
    if (typeof request !== 'object' || request === null) {
      return this.invalid('request', 'Process request must be an object');
    }
    if (typeof request.executable !== 'string' || request.executable.trim() === '') {
      return this.invalid('executable', 'Process executable must not be blank');
    }
    if (request.executable.includes('\0')) {
      return this.invalid('executable', 'Process executable must not contain NUL');
    }
    if (
      request.arguments !== undefined &&
      (!Array.isArray(request.arguments) ||
        Array.from(request.arguments).some(argument => typeof argument !== 'string' || argument.includes('\0')))
    ) {
      return this.invalid('arguments', 'Process arguments must be NUL-free strings');
    }
    if (
      request.cwd !== undefined &&
      (typeof request.cwd !== 'string' || request.cwd === '' || request.cwd.includes('\0'))
    ) {
      return this.invalid('cwd', 'Process cwd must be a non-empty NUL-free string');
    }
    if (
      request.environment !== undefined &&
      (typeof request.environment !== 'object' ||
        request.environment === null ||
        Array.isArray(request.environment) ||
        ![Object.prototype, null].includes(Object.getPrototypeOf(request.environment)))
    ) {
      return this.invalid('environment', 'Process environment must be a string record');
    }
    if (
      request.environment !== undefined &&
      Object.entries(request.environment).some(
        ([key, value]) =>
          key === '' || key.includes('=') || key.includes('\0') || typeof value !== 'string' || value.includes('\0'),
      )
    ) {
      return this.invalid('environment', 'Process environment entries must be valid NUL-free strings');
    }
    if (request.stdin !== undefined && typeof request.stdin !== 'string') {
      return this.invalid('stdin', 'Process stdin must be a string');
    }
    if (request.timeoutMs !== undefined && (!Number.isInteger(request.timeoutMs) || request.timeoutMs <= 0)) {
      return this.invalid('timeoutMs', 'Process timeoutMs must be a positive integer');
    }

    return this.accept(
      Object.freeze({
        executable: request.executable,
        ...(request.arguments === undefined ? {} : { arguments: Object.freeze([...request.arguments]) }),
        ...(request.cwd === undefined ? {} : { cwd: request.cwd }),
        ...(request.environment === undefined ? {} : { environment: Object.freeze({ ...request.environment }) }),
        ...(request.stdin === undefined ? {} : { stdin: request.stdin }),
        ...(request.timeoutMs === undefined ? {} : { timeoutMs: request.timeoutMs }),
      }),
    );
  }

  validateRequest(request: ProcessRequest): Result<ProcessRequest, SystemError> {
    return this.toResult(this.checkRequest(request));
  }

  checkOutput(output: ProcessOutput): Checked<ProcessOutput, SystemError> {
    if (
      typeof output !== 'object' ||
      output === null ||
      !Number.isInteger(output.exitCode) ||
      typeof output.stdout !== 'string' ||
      typeof output.stderr !== 'string'
    ) {
      return this.reject(
        new PortError(
          'system',
          'invalid-input',
          'execute',
          'Process output must contain an integer exit code and text streams',
        ),
      );
    }
    return this.accept(Object.freeze({ exitCode: output.exitCode, stderr: output.stderr, stdout: output.stdout }));
  }

  validateOutput(output: ProcessOutput): Result<ProcessOutput, SystemError> {
    return this.toResult(this.checkOutput(output));
  }

  private invalid(field: string, message: string): Checked<never, SystemError> {
    return this.reject(new PortError('system', 'invalid-input', 'execute', message, { field }));
  }
}

export type { ProcessOutput, ProcessRequest, System };
export { SystemPolicy };
