import { describe, it } from 'bun:test';
import 'should';
import { OtelBlockFixtures } from '../../src/test-helper';
import { otelBlockSchema } from '../../src/lib/schema';

const fixtures = new OtelBlockFixtures();

describe('OtelBlockFixtures', () => {
  it.each([
    ['canonical', fixtures.canonical()],
    ['disabled', fixtures.disabled()],
    ['console', fixtures.console()],
    ['otlp', fixtures.otlp()],
    ['otlp on a custom endpoint', new OtelBlockFixtures('https://collector.example:4318').otlp()],
  ])('should ship a %s block the schema accepts', (_label, block) => {
    // Arrange
    const candidate = block;

    // Act
    const actual = otelBlockSchema.safeParse(candidate);

    // Assert
    actual.success.should.be.true();
  });

  it('should switch exactly what each fixture names', () => {
    // Arrange
    const signals = ['logs', 'metrics', 'traces'] as const;

    // Act
    const shape = (block: ReturnType<typeof fixtures.canonical>) =>
      signals.map(signal => [
        block[signal].enabled,
        block[signal].exporter.console.enabled,
        block[signal].exporter.otlp.enabled,
      ]);

    // Assert
    shape(fixtures.canonical()).should.eql([
      [true, false, false],
      [true, false, false],
      [true, false, false],
    ]);
    shape(fixtures.disabled()).should.eql([
      [false, false, false],
      [false, false, false],
      [false, false, false],
    ]);
    shape(fixtures.console()).should.eql([
      [true, true, false],
      [true, true, false],
      [true, true, false],
    ]);
    shape(fixtures.otlp()).should.eql([
      [true, false, true],
      [true, false, true],
      [true, false, true],
    ]);
    fixtures.otlp().traces.exporter.otlp.endpoint.should.eql('http://otel-collector:4318');
  });

  it('should hand out frozen blocks', () => {
    // Arrange
    const block = fixtures.otlp();

    // Act
    const frozen = [Object.isFrozen(block), Object.isFrozen(block.metrics), Object.isFrozen(fixtures.canonical())];

    // Assert
    frozen.should.eql([true, true, true]);
  });
});
