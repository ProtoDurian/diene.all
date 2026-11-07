import { expectRedBecause as expectRedBecauseWithin } from './helpers.ts';
import { expectGreen } from './dotnet.ts';

export const PACKAGE_VALIDATE = 'nix develop .#ci -c ./scripts/validate/dotnet-package.sh';

// Same cap as ./dotnet.ts: a cold .NET restore and build runs past 240 s.
const DOTNET_TIMEOUT_MS = 600000;

export async function expectRedBecause(
  repo: any,
  command: string,
  label: string,
  reasons: readonly string[],
): Promise<string> {
  return expectRedBecauseWithin(repo, command, label, reasons, { timeoutMs: DOTNET_TIMEOUT_MS });
}

export async function manifestVersion(repo: any): Promise<string> {
  const version = /<Version>([^<]+)<\/Version>/.exec(await repo.read('Version.props'))?.[1];
  if (!version) {
    throw new Error('Version.props declares no <Version>');
  }
  return version;
}

export async function packPackages(repo: any, label: string): Promise<void> {
  await expectGreen(
    repo,
    "nix develop .#ci -c bash -c 'rm -rf artifacts/package && mkdir -p artifacts/package && dotnet pack dotnet-base.slnx -c Release --output artifacts/package'",
    label,
  );
}
