export async function withCleanup<T>(
  operation: () => Promise<T>,
  cleanup: () => Promise<void>,
  onCleanupFailure: (error: unknown) => void,
): Promise<T> {
  let result: T;

  try {
    result = await operation();
  } catch (error) {
    try {
      await cleanup();
    } catch (cleanupError) {
      try {
        onCleanupFailure(cleanupError);
      } catch {
        // Best-effort: must not replace the operation error.
      }
    }
    throw error;
  }

  await cleanup();
  return result;
}
