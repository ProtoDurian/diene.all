import { expectGreen } from './lib/helpers.ts';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  setup: { post: ['nix develop .#ci -c dart pub get --offline', 'rm -f .git/hooks/pre-commit .git/hooks/commit-msg'] },
  probes: [
    {
      name: 'baseline-pub-workspace-resolution-green',
      description:
        'cached dart pub get resolves the workspace member and its four hosted runtime dependencies from pub.dev',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(repo, 'nix develop .#ci -c dart pub get --offline', 'pub-workspace-resolution');
        const config = JSON.parse(await repo.read('.dart_tool/package_config.json'));
        const member = (config.packages ?? []).find((entry: any) => entry.name === 'diene_core_utils');
        if (!member || !String(member.rootUri).endsWith('packages/diene_core_utils')) {
          throw new Error('pub-workspace-resolution: package_config.json does not resolve the diene_core_utils member');
        }
        for (const name of ['diene_interfaces', 'diene_problems', 'diene_result', 'unorm_dart']) {
          const hosted = (config.packages ?? []).find((entry: any) => entry.name === name);
          if (!hosted || !new RegExp(`/hosted/pub\\.dev/${name}-[^/]+/?$`).test(String(hosted.rootUri))) {
            throw new Error(`pub-workspace-resolution: ${name} is not resolved from pub.dev (${hosted?.rootUri})`);
          }
        }
      },
    },
  ],
};
