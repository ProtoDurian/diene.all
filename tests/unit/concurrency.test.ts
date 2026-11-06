import { describe, it } from 'bun:test';
import 'should';
import { ConcurrencyMapper } from '../../src/lib/concurrency';
import { Timing } from '../../src/lib/timing';

const timing = new Timing();

describe('ConcurrencyMapper.mapWithConcurrency', () => {
  it('should preserve input order regardless of completion order', async () => {
    // Arrange
    const mapper = new ConcurrencyMapper();

    // Act
    const actual = await mapper.mapWithConcurrency([40, 10, 30, 20, 0], 2, async item => {
      await timing.sleep(item / 1000);
      return item * 2;
    });

    // Assert
    actual.should.deepEqual([80, 20, 60, 40, 0]);
  });

  it('should pass the index to the mapper', async () => {
    // Arrange
    const mapper = new ConcurrencyMapper();

    // Act
    const actual = await mapper.mapWithConcurrency(['a', 'b', 'c'], 3, (item, index) => `${index}:${item}`);

    // Assert
    actual.should.deepEqual(['0:a', '1:b', '2:c']);
  });

  it('should never exceed the concurrency bound', async () => {
    // Arrange
    const mapper = new ConcurrencyMapper();
    let active = 0;
    let peak = 0;

    // Act
    await mapper.mapWithConcurrency(
      Array.from({ length: 12 }, (_, index) => index),
      3,
      async item => {
        active += 1;
        peak = Math.max(peak, active);
        await timing.sleep(0.005);
        active -= 1;
        return item;
      },
    );

    // Assert
    peak.should.equal(3);
  });

  it('should return an empty array for empty input', async () => {
    // Arrange
    const mapper = new ConcurrencyMapper();

    // Act
    const actual = await mapper.mapWithConcurrency([], 4, item => item);

    // Assert
    actual.should.deepEqual([]);
  });

  it.each([{ concurrency: 0 }, { concurrency: -2 }, { concurrency: 1.5 }, { concurrency: Number.NaN }])(
    'should reject concurrency $concurrency with a RangeError',
    async ({ concurrency }) => {
      // Arrange
      const mapper = new ConcurrencyMapper();

      // Act
      const actual = mapper.mapWithConcurrency([1, 2, 3], concurrency, item => item);

      // Assert
      await actual.should.be.rejectedWith(RangeError);
    },
  );

  it('should propagate a mapper rejection', async () => {
    // Arrange
    const mapper = new ConcurrencyMapper();
    const boom = new Error('mapper failed');

    // Act
    const actual = mapper.mapWithConcurrency([1, 2, 3], 2, async item => {
      if (item === 2) throw boom;
      return item;
    });

    // Assert
    await actual.should.be.rejectedWith(boom);
  });

  it('should start no further item once a mapper rejects', async () => {
    // Arrange
    const mapper = new ConcurrencyMapper();
    const started: number[] = [];

    // Act
    const actual = mapper.mapWithConcurrency([0, 1, 2, 3, 4, 5], 2, async item => {
      started.push(item);
      if (item === 0) throw new Error('mapper failed');
      await timing.sleep(0.005);
      return item;
    });
    await actual.catch(() => undefined);
    await timing.sleep(0.03);

    // Assert
    await actual.should.be.rejectedWith('mapper failed');
    started.should.deepEqual([0, 1]);
  });
});
