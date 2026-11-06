import { isRecord } from '@atomicloud/diene.core-utils';
import type { ConfigRecord } from './merge.js';

const BASE_LANDSCAPE = 'base';
const LANDSCAPE_TOKEN = /^[a-z0-9][a-z0-9-]*$/;

class LandscapeResolutionError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'LandscapeResolutionError';
  }
}

class LandscapeResolver {
  // biome-ignore lint/complexity/noUselessConstructor: Bun coverage counts an implicit constructor as an uncovered function
  constructor() {}

  resolve(explicit: string | undefined, base: ConfigRecord): string {
    const fromBase = isRecord(base.app) && typeof base.app.landscape === 'string' ? base.app.landscape : undefined;
    const given = explicit?.trim() === '' ? undefined : explicit;
    const chosen = (given ?? fromBase ?? BASE_LANDSCAPE).trim();
    if (chosen === '' || chosen === BASE_LANDSCAPE) return BASE_LANDSCAPE;
    if (!LANDSCAPE_TOKEN.test(chosen)) throw new LandscapeResolutionError(`invalid landscape name: "${chosen}"`);
    return chosen;
  }
}

export { BASE_LANDSCAPE, LandscapeResolutionError, LandscapeResolver };
