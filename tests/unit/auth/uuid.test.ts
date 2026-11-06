import { describe, it } from 'bun:test';
import 'should';
import type { IClock, IRandomSource } from '../../../src/lib/auth/interfaces';
import { UuidV7Generator } from '../../../src/lib/auth/uuid';

class FixedClock implements IClock {
  constructor(private readonly at: Date) {}

  now(): Date {
    return this.at;
  }
}

class FilledRandom implements IRandomSource {
  constructor(private readonly fill: number) {}

  bytes(length: number): Uint8Array {
    return new Uint8Array(length).fill(this.fill);
  }
}

describe('UuidV7Generator', () => {
  it('should put the millisecond timestamp, version 7 and the RFC variant in place', () => {
    // Arrange
    const subject = new UuidV7Generator(new FixedClock(new Date(0x0190a6e01234)), new FilledRandom(0xff));

    // Act
    const actual = subject.next();

    // Assert
    actual.should.equal('0190a6e0-1234-7fff-bfff-ffffffffffff');
  });

  it('should keep lowercase hex with zero random bytes', () => {
    // Arrange
    const subject = new UuidV7Generator(new FixedClock(new Date('2026-03-15T14:30:00.000Z')), new FilledRandom(0));

    // Act
    const actual = subject.next();

    // Assert
    actual.should.match(/^[0-9a-f]{8}-[0-9a-f]{4}-7000-8000-000000000000$/);
  });

  it('should sort by creation time', () => {
    // Arrange
    const random = new FilledRandom(0x5a);
    const earlier = new UuidV7Generator(new FixedClock(new Date(1_000)), random);
    const later = new UuidV7Generator(new FixedClock(new Date(2_000)), random);

    // Act
    const actual = [later.next(), earlier.next()].sort();

    // Assert
    actual.should.deepEqual([earlier.next(), later.next()]);
  });
});
