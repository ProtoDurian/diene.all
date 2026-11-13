import { expectGreen, expectRed } from './lib/helpers.ts';

const CHECK = 'nix develop .#ci -c ./scripts/local/action-majors.sh';
const RELEASE_NOTE = '.github/workflows/⚡reusable-release-note.yaml';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-action-majors-green',
      description: 'Every trusted action is on its recorded major.',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(repo, CHECK, 'action-majors');
      },
    },
    {
      name: 'mutation-action-majors-below-caught',
      description: 'actions/checkout@v4 (below its recorded major) must turn the action-majors mechanism red.',
      kind: 'mutation',
      expectedImpact: [],
      async run(repo: any) {
        await repo.patch(RELEASE_NOTE, { find: 'actions/checkout@v7', replace: 'actions/checkout@v4' });
        await expectRed(repo, CHECK, 'action-majors');
      },
    },
    {
      name: 'mutation-action-majors-unlisted-caught',
      description: 'A trusted action missing from the recorded list must turn the action-majors mechanism red.',
      kind: 'mutation',
      expectedImpact: [],
      async run(repo: any) {
        await repo.patch('.github/action-majors.yaml', { find: '  actions/checkout: 7\n', replace: '' });
        await expectRed(repo, CHECK, 'action-majors');
      },
    },
    {
      name: 'mutation-action-majors-empty-caught',
      description: 'An empty recorded list must turn the action-majors mechanism red.',
      kind: 'mutation',
      expectedImpact: [],
      async run(repo: any) {
        await repo.write('.github/action-majors.yaml', 'majors: {}\n');
        await expectRed(repo, CHECK, 'action-majors');
      },
    },
  ],
};
