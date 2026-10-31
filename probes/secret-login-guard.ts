export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      // No dev shell on purpose: the guard fires before infisical is reached.
      name: 'baseline-secret-login-guard-refuses-actions',
      description: 'The secrets helper refuses the removed fetch/scan actions: exit 1 with a ❌ reason.',
      kind: 'baseline',
      async run(repo: any) {
        for (const stale of ['fetch', 'scan']) {
          const result = await repo.exec(`./scripts/local/secrets.sh ${stale}`);
          if (result.exitCode !== 1) {
            throw new Error(`secrets.sh exited ${result.exitCode} on the removed '${stale}' action, expected 1`);
          }
          const output = `${result.stdout}${result.stderr}`;
          if (!output.includes('❌') || !output.includes('secrets.sh takes no arguments')) {
            throw new Error(`secrets.sh refused '${stale}' without saying why: ${output}`);
          }
        }
      },
    },
  ],
};
