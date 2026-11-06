import { describe, it } from 'bun:test';
import 'should';
import { BuildTimeValueMapper } from '../../src/lib/build-time.js';

const mapper = new BuildTimeValueMapper();

describe('BuildTimeValueMapper.map', () => {
  it.each([
    {
      label: 'only prefixed, non-blank variables',
      env: {
        ATOMI_CLIENT__FARO__BUILD__KEY: 'secret',
        ATOMI_CLIENT__NAME: 'app',
        ATOMI_BLANK: '',
        OTHER__VAR: 'ignored',
        ATOMI_UNSET: undefined,
      },
      expected: { ATOMI_CLIENT__FARO__BUILD__KEY: 'secret', ATOMI_CLIENT__NAME: 'app' },
    },
    { label: 'nothing when no variable matches', env: { PATH: '/usr/bin' }, expected: {} },
  ])('should keep $label', ({ env, expected }) => {
    // Arrange
    const prefix = 'ATOMI_';

    // Act
    const actual = mapper.map(env, prefix);

    // Assert
    actual.should.deepEqual(expected);
  });
});
