import { readFileSync } from 'node:fs';
import type { AgentOptions } from 'node:https';
import type { OtlpTlsFile, OtlpTlsFiles } from '../../lib/endpoint.js';

interface TlsFileReader {
  read(path: string): Buffer;
}

class NodeTlsFileReader implements TlsFileReader {
  // biome-ignore lint/complexity/noUselessConstructor: Bun coverage counts an implicit constructor as an uncovered function
  constructor() {}

  read(path: string): Buffer {
    return readFileSync(path);
  }
}

class OtlpTlsFileError extends Error {
  constructor(
    readonly variable: string,
    readonly path: string,
    override readonly cause: unknown,
  ) {
    super(`${variable} names an unreadable file ${path}: ${cause instanceof Error ? cause.message : String(cause)}`, {
      cause,
    });
    this.name = 'OtlpTlsFileError';
  }
}

class OtlpAgentOptionsFactory {
  constructor(private readonly files: TlsFileReader = new NodeTlsFileReader()) {}

  create(tls: OtlpTlsFiles): AgentOptions {
    return {
      keepAlive: true,
      ...Object.fromEntries(Object.entries(tls).map(([material, file]) => [material, this.read(file)])),
    };
  }

  private read(file: OtlpTlsFile): Buffer {
    try {
      return this.files.read(file.path);
    } catch (cause) {
      throw new OtlpTlsFileError(file.variable, file.path, cause);
    }
  }
}

export type { TlsFileReader };
export { NodeTlsFileReader, OtlpAgentOptionsFactory, OtlpTlsFileError };
