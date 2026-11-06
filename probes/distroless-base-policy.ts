import { expectImagePolicyGreen, expectImagePolicyRed } from './lib/go.ts';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-distroless-policy-green',
      description: 'The runtime image uses the declared distroless base.',
      kind: 'baseline',
      async run(repo: any) {
        await expectImagePolicyGreen(repo, 'distroless');
      },
    },
    {
      name: 'mutation-distroless-policy-caught',
      description: 'Replacing the runtime with Alpine must turn the distroless policy red.',
      kind: 'mutation',
      async run(repo: any) {
        const original = await repo.read('infra/Dockerfile');
        try {
          await repo.patch('infra/Dockerfile', {
            find: 'FROM gcr.io/distroless/static-debian12:nonroot AS runtime',
            replace: 'FROM alpine:3.22 AS runtime',
          });
          await expectImagePolicyRed(repo, 'distroless');
        } finally {
          await repo.write('infra/Dockerfile', original);
        }
      },
    },
  ],
};
