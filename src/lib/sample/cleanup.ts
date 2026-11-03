import type { ILogger } from './interfaces';

export class Cleanup {
  constructor(private readonly logger: ILogger) {}

  async run<T>(operation: () => Promise<T>, cleanup: () => Promise<void>): Promise<T> {
    let result: T;

    try {
      result = await operation();
    } catch (error) {
      try {
        await cleanup();
      } catch (cleanupError) {
        try {
          this.logger.warn({ reason: String(cleanupError) }, 'cleanup failed after the operation failed');
        } catch {
          // Best-effort: must not replace the operation error.
        }
      }
      throw error;
    }

    await cleanup();
    return result;
  }
}
