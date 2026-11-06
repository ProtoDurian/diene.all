#!/usr/bin/env bash
set -euo pipefail

version="$(xmlstarlet sel -t -v '/Project/PropertyGroup/Version' Version.props)"
artifacts="artifacts/package"

rm -rf "${artifacts}"
mkdir -p "${artifacts}"

echo "📦 Packing library and TestHelper at ${version}..."
dotnet pack dotnet-base.slnx -c Release --output "${artifacts}"

./scripts/validate/dotnet-package.sh inventory "${artifacts}" "${version}"
./scripts/validate/dotnet-package.sh metadata "${artifacts}" "${version}"
./scripts/validate/dotnet-package.sh symbols "${artifacts}" "${version}"

scratch="$(mktemp -d)"
trap 'rm -rf "${scratch}"' EXIT

echo "🧪 Restoring both packages into a scratch consumer..."
dotnet new console --framework net10.0 --no-restore --output "${scratch}" >/dev/null
dotnet add "${scratch}" package AtomiCloud.Diene.Interfaces --version "${version}" --source "$(pwd)/${artifacts}" --no-restore >/dev/null
dotnet add "${scratch}" package AtomiCloud.Diene.Interfaces.TestHelper --version "${version}" --source "$(pwd)/${artifacts}" --no-restore >/dev/null
printf '%s\n' \
  'using AtomiCloud.Diene.Interfaces;' \
  'using AtomiCloud.Diene.Interfaces.TestHelper;' \
  'using AtomiCloud.Diene.Results.TestHelper;' \
  '' \
  'var vfs = new InMemoryVfs();' \
  'var report = await SeamContracts.Vfs(vfs, "/scratch");' \
  'report.Should().BeConformant();' \
  '' \
  'var sink = new InMemoryLoggerSink();' \
  'sink.Emit(new LogRecord(DateTimeOffset.UnixEpoch, LogLevel.Info, "scratch")).Should().BeOk();' \
  'sink.Should().HaveLogged(LogLevel.Info, "scratch");' \
  '' \
  '(await vfs.ReadText("/absent")).Should().BeSeamErr(SeamKind.Vfs, "not_found");' >"${scratch}/Program.cs"
cat >"${scratch}/nuget.config" <<EOF
<configuration>
  <packageSources>
    <clear />
    <add key="local" value="$(pwd)/${artifacts}" />
    <add key="nuget.org" value="https://api.nuget.org/v3/index.json" />
  </packageSources>
  <packageSourceMapping>
    <packageSource key="local">
      <package pattern="AtomiCloud.Diene.Interfaces" />
      <package pattern="AtomiCloud.Diene.Interfaces.TestHelper" />
    </packageSource>
    <packageSource key="nuget.org">
      <package pattern="*" />
    </packageSource>
  </packageSourceMapping>
</configuration>
EOF
dotnet restore "${scratch}" --packages "${scratch}/packages" >/dev/null
dotnet build "${scratch}" -c Release --no-restore >/dev/null

echo "✅ Package validation and scratch consumption passed"
