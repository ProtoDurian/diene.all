import type { ErrorPortalConfig } from '@atomicloud/diene.problems';

const portal: ErrorPortalConfig = Object.freeze({
  scheme: 'https',
  host: 'errors.atomi.cloud',
  landscape: 'raichu',
  platform: 'nitroso',
  service: 'zinc',
  module: 'api',
});

function thrown(action: () => unknown): Error {
  try {
    action();
  } catch (error: unknown) {
    return error as Error;
  }
  throw new Error('expected the action to throw');
}

export { portal, thrown };
