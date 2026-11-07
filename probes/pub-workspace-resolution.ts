import { expectGreen } from './lib/helpers.ts';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  setup: {
    post: ['nix develop .#ci -c flutter pub get --offline', 'rm -f .git/hooks/pre-commit .git/hooks/commit-msg'],
  },
  probes: [
    {
      name: 'baseline-pub-workspace-resolution-green',
      description: 'cached flutter pub get resolves the workspace member and its hosted runtime dependencies',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(repo, 'nix develop .#ci -c flutter pub get --offline', 'pub-workspace-resolution');
        const config = JSON.parse(await repo.read('.dart_tool/package_config.json'));
        const member = (config.packages ?? []).find((entry: any) => entry.name === 'diene_auth_engine');
        if (!member || !String(member.rootUri).endsWith('packages/diene_auth_engine')) {
          throw new Error(
            'pub-workspace-resolution: package_config.json does not resolve the diene_auth_engine member',
          );
        }
        for (const name of ['diene_problems', 'diene_result', 'http', 'logto_dart_sdk', 'meta']) {
          const hosted = (config.packages ?? []).find((entry: any) => entry.name === name);
          if (!hosted || !new RegExp(`/hosted/pub\\.dev/${name}-[^/]+/?$`).test(String(hosted.rootUri))) {
            throw new Error(`pub-workspace-resolution: ${name} is not resolved from pub.dev (${hosted?.rootUri})`);
          }
        }
      },
    },
  ],
};
