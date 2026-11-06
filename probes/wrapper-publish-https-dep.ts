import { defineGate } from './lib/definition.ts';
import { expectGreen, expectRed } from './lib/helpers.ts';

export default defineGate({
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  baseline: {
    name: 'baseline-wrapper-publish-https-dep-green',
    description: 'A chart whose dependency lives in a repository URL packages with an empty Helm repo config.',
    async run(repo: any) {
      await expectGreen(
        repo,
        'nix develop .#ci -c ./scripts/validate/helm-wrapper.sh publish-https-dep',
        'wrapper-publish-https-dep',
      );
    },
  },
  mutation: {
    name: 'mutation-wrapper-publish-https-dep-caught',
    description: 'Without the throwaway repo registration, helm dependency build refuses the URL dependency.',
    expectedImpact: [],
    async run(repo: any) {
      const path = 'scripts/ci/publish.sh';
      const original = await repo.read(path);
      try {
        await repo.patch(path, {
          find: '  helm repo add "chart-dep-${index}" "${url}" >/dev/null',
          replace: '  : "${url}"',
        });
        await expectRed(
          repo,
          'nix develop .#ci -c ./scripts/validate/helm-wrapper.sh publish-https-dep',
          'wrapper-publish-https-dep',
        );
      } finally {
        await repo.write(path, original);
      }
    },
  },
});
