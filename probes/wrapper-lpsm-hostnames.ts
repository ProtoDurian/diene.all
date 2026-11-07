import { defineSmoke } from './lib/definition.ts';
import { expectGreen } from './lib/helpers.ts';

export default defineSmoke({
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  baseline: {
    name: 'baseline-wrapper-lpsm-hostnames-green',
    description:
      'Ordinary, localhost, Boron and ENTEI hostname vectors, inverse parsing, opaque-instance and identity-issuer refusals, normalization and collision checks pass.',
    async run(repo: any) {
      await expectGreen(repo, 'nix develop .#ci -c ./scripts/validate/helm-wrapper.sh lpsm', 'wrapper-lpsm-hostnames');
    },
  },
});
