import { describe, it } from 'bun:test';
import 'should';
import { BuildTimeValueMapper } from '../../src/lib/build-time.js';

const mapper = new BuildTimeValueMapper();

describe('BuildTimeValueMapper.map', () => {
  it.each([
    {
      label: 'only non-blank client values',
      env: {
        ATOMI_CLIENT__NAME: 'app',
        ATOMI_CLIENT__API__URL: 'https://api',
        ATOMI_CLIENT__BLANK: '',
        ATOMI_CLIENT__UNSET: undefined,
        OTHER_CLIENT__NAME: 'ignored',
      },
      expected: { ATOMI_CLIENT__NAME: 'app', ATOMI_CLIENT__API__URL: 'https://api' },
    },
    {
      label: 'no build-time secret and no server value',
      env: {
        ATOMI_CLIENT__FARO__BUILD__KEY: 'secret',
        ATOMI_CLIENT__BUILD__TOKEN: 'secret',
        ATOMI_CLIENT__faro__build__key: 'secret',
        ATOMI_SERVER__DB__PASSWORD: 'pw',
        ATOMI_SHARED__NAME: 'shared',
        ATOMI_CLIENT__FARO__URL: 'https://faro',
      },
      expected: { ATOMI_CLIENT__FARO__URL: 'https://faro' },
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
