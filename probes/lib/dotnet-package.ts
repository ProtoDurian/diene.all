import { expectGreen } from './dotnet.ts';

export const PACKAGE_VALIDATE = 'nix develop .#ci -c ./scripts/validate/dotnet-package.sh';

export async function packPackages(repo: any, label: string): Promise<void> {
  await expectGreen(
    repo,
    "nix develop .#ci -c bash -c 'rm -rf artifacts/package && mkdir -p artifacts/package && dotnet pack dotnet-base.slnx -c Release --output artifacts/package'",
    label,
  );
}
