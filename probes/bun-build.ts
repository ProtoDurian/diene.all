import { expectBunGreen } from './lib/bun-command.ts';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-bun-build-green',
      description: 'The build task produces the web app and the Worker bundle.',
      kind: 'baseline',
      async run(repo: any) {
        await expectBunGreen(
          repo,
          "nix develop .#ci -c bash -lc './scripts/local/setup.sh && task build'",
          'bun-build',
        );
        for (const artifact of ['dist/web/index.html', 'dist/worker/index.js']) {
          if ((await repo.glob(artifact)).length !== 1) throw new Error(`${artifact} is missing`);
        }
      },
    },
  ],
};
