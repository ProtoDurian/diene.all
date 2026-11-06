import type { IClock, IRandomSource } from './interfaces';

export class UuidV7Generator {
  constructor(
    private readonly clock: IClock,
    private readonly random: IRandomSource,
  ) {}

  next(): string {
    const bytes = this.random.bytes(16);
    let millis = this.clock.now().getTime();
    for (let index = 5; index >= 0; index--) {
      bytes[index] = millis % 256;
      millis = Math.floor(millis / 256);
    }
    bytes[6] = ((bytes[6] ?? 0) & 0x0f) | 0x70;
    bytes[8] = ((bytes[8] ?? 0) & 0x3f) | 0x80;
    const hex = Array.from(bytes, byte => byte.toString(16).padStart(2, '0')).join('');
    return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20)}`;
  }
}
