import { expectImagePolicyGreen, expectImagePolicyRed } from './lib/go.ts';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-nonroot-policy-green',
      description: 'The runtime image declares the unprivileged distroless identity.',
      kind: 'baseline',
      async run(repo: any) {
        await expectImagePolicyGreen(repo, 'nonroot');
      },
    },
    {
      name: 'mutation-nonroot-policy-caught',
      description: 'A lowercase indented root override after the valid declaration must turn the nonroot policy red.',
      kind: 'mutation',
      async run(repo: any) {
        const original = await repo.read('infra/Dockerfile');
        try {
          // Keep the compliant USER: Docker uses the last one.
          await repo.patch('infra/Dockerfile', {
            find: 'USER 65532:65532\n',
            replace: 'USER 65532:65532\n  user 0:0\n',
          });
          await expectImagePolicyRed(repo, 'nonroot');
        } finally {
          await repo.write('infra/Dockerfile', original);
        }
      },
    },
  ],
};
