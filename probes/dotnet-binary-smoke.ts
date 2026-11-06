import { defineSmoke } from './lib/definition.ts';
import { expectGreen } from './lib/dotnet.ts';

// String.raw keeps the shell's backslashes; $var is shell, not a template.
const invocations = String.raw`
set -euo pipefail
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

dotnet --version >/dev/null
dotnet sln dotnet-base.slnx list | rg -q 'App/App.csproj'

mkdir -p "$tmp/smoke"
printf '%s\n' '<Project Sdk="Microsoft.NET.Sdk">' '  <PropertyGroup>' '    <OutputType>Exe</OutputType>' '    <TargetFramework>net10.0</TargetFramework>' '    <ImplicitUsings>enable</ImplicitUsings>' '  </PropertyGroup>' '</Project>' >"$tmp/smoke/Smoke.csproj"
printf '%s\n' 'Console.WriteLine("smoke");' >"$tmp/smoke/Program.cs"
dotnet restore "$tmp/smoke/Smoke.csproj" >/dev/null

dotnetlint --version >/dev/null
(cd "$tmp/smoke" && dotnetlint) | rg -q 'Processing project:'

dn-inspect --version >/dev/null
dotnet tool restore >/dev/null
dn-inspect --projects "$tmp/smoke/Smoke.csproj" --filter '^$' | rg -q 'Total: 0 issue\(s\)'

xmlstarlet --version >/dev/null
[ "$(xmlstarlet sel -t -v 'count(/Project/PropertyGroup/Version)' Version.props)" = "1" ]

echo "dotnet toolchain invocations passed"
`;

export default defineSmoke({
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  baseline: {
    name: 'baseline-dotnet-binary-smoke-invokes',
    description: 'Every binary this node declares answers its version and one real operation in the dev shell.',
    async run(repo: any) {
      await repo.write('probe-dotnet-invocations.sh', invocations);
      try {
        await expectGreen(repo, 'nix develop .#default -c bash probe-dotnet-invocations.sh', 'dotnet-binary-smoke');
      } finally {
        await repo.exec('rm -f probe-dotnet-invocations.sh');
      }
    },
  },
});
