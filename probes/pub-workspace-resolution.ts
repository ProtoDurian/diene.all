import { expectGreen } from './lib/helpers.ts';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  setup: { post: ['nix develop .#ci -c dart pub get --offline', 'rm -f .git/hooks/pre-commit .git/hooks/commit-msg'] },
  probes: [
    {
      name: 'baseline-pub-workspace-resolution-green',
      description: 'cached dart pub get resolves the workspace and writes a package config naming the member',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(repo, 'nix develop .#ci -c dart pub get --offline', 'pub-workspace-resolution');
        const config = JSON.parse(await repo.read('.dart_tool/package_config.json'));
        const member = (config.packages ?? []).find((entry: any) => entry.name === 'diene_auth_engine');
        if (!member || !String(member.rootUri).endsWith('packages/diene_auth_engine')) {
          throw new Error(
            'pub-workspace-resolution: package_config.json does not resolve the diene_auth_engine member',
          );
        }
      },
    },
  ],
};
