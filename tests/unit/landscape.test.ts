import { describe, it } from 'bun:test';
import 'should';
import { BASE_LANDSCAPE, LandscapeResolutionError, LandscapeResolver } from '../../src/lib/landscape.js';
import type { ConfigRecord } from '../../src/lib/merge.js';

const resolver = new LandscapeResolver();

describe('LandscapeResolver.resolve', () => {
  it.each([
    {
      label: 'an explicit host landscape',
      explicit: 'raichu',
      base: { app: { landscape: 'pichu' } },
      expected: 'raichu',
    },
    {
      label: 'the service-tree app.landscape',
      explicit: undefined,
      base: { app: { landscape: 'pikachu' } },
      expected: 'pikachu',
    },
    { label: 'base when neither is present', explicit: undefined, base: {}, expected: BASE_LANDSCAPE },
    { label: 'base for an explicit "base"', explicit: 'base', base: {}, expected: BASE_LANDSCAPE },
    { label: 'base for a blank string', explicit: '   ', base: {}, expected: BASE_LANDSCAPE },
    {
      label: 'base for a non-string app.landscape',
      explicit: undefined,
      base: { app: { landscape: 42 } },
      expected: BASE_LANDSCAPE,
    },
    { label: 'base for a non-object app', explicit: undefined, base: { app: 'x' }, expected: BASE_LANDSCAPE },
    { label: 'a trimmed explicit landscape', explicit: ' prod ', base: {}, expected: 'prod' },
  ])('should resolve $label', ({ explicit, base, expected }) => {
    // Arrange
    const config: ConfigRecord = base;

    // Act
    const actual = resolver.resolve(explicit, config);

    // Assert
    actual.should.equal(expected);
  });

  it.each(['../etc/passwd', 'Prod', '-lead'])('should reject the unsafe landscape token %s', token => {
    // Arrange
    const base: ConfigRecord = {};

    // Act
    const act = () => resolver.resolve(token, base);

    // Assert
    act.should.throw(LandscapeResolutionError);
  });
});
