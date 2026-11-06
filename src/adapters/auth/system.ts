import type { IClock, IRandomSource } from '../../lib/auth/interfaces';

export class SystemClock implements IClock {
  constructor(private readonly epochMillis: () => number = Date.now) {}

  now(): Date {
    return new Date(this.epochMillis());
  }
}

export class CryptoRandomSource implements IRandomSource {
  constructor(private readonly source: Pick<Crypto, 'getRandomValues'> = crypto) {}

  bytes(length: number): Uint8Array {
    return this.source.getRandomValues(new Uint8Array(length));
  }
}
