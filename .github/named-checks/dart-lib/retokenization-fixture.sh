#!/usr/bin/env bash
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"
# index tree == HEAD in CI; keeps local staged mutations visible
tree="$(git write-tree)"
work="$(mktemp -d)"
trap 'rm -rf "${work}"' EXIT
copy="${work}/fixture"
from_pkg="packages/diene_dart_lib"
to_pkg="packages/diene_fixture"

command -v dart >/dev/null || { echo "❌ dart is not on PATH; run inside the .#ci shell" >&2 && exit 1; }

retoken() { sed -e 's/diene_dart_lib/diene_fixture/g' -e 's/diene-dart-lib/diene-fixture/g' -e 's/diene\.dart_lib/diene.dart_fixture/g'; }

mkdir -p "${copy}"
git archive "${tree}" -- pubspec.yaml analysis_options.yaml "${from_pkg}" | tar -x -C "${copy}"
[[ -f "${copy}/${from_pkg}/lib/diene_dart_lib.dart" ]] || { echo "❌ ${from_pkg}/lib/diene_dart_lib.dart missing; nothing to retokenize" >&2 && exit 1; }

renamed=0
while IFS= read -r -d '' p; do
  base="$(basename "${p}")"
  mv -- "${p}" "$(dirname "${p}")/$(retoken <<<"${base}")"
  renamed=$((renamed + 1))
done < <(find "${copy}" -depth \( -name '*diene_dart_lib*' -o -name '*diene-dart-lib*' \) -print0)

edited=0
while IFS= read -r -d '' f; do
  retoken <"${f}" >"${f}.new" && mv -- "${f}.new" "${f}"
  edited=$((edited + 1))
done < <(grep -rlIZ -e diene_dart_lib -e diene-dart-lib -e 'diene\.dart_lib' "${copy}" || true)

leftover="$(grep -rnI -i -e diene_dart_lib -e diene-dart-lib -e 'dart_lib' -e 'dart-lib' "${copy}" || true)"
[[ -z ${leftover} ]] || { echo "❌ retokenization left the old identity behind:"$'\n'"${leftover}" >&2 && exit 1; }
for want in "${to_pkg}/lib/diene_fixture.dart" "${to_pkg}/skills/diene-fixture-usage/SKILL.md"; do
  [[ -f "${copy}/${want}" ]] || { echo "❌ retokenized ${want} missing" >&2 && exit 1; }
done
[[ ${renamed} -gt 0 && ${edited} -gt 0 ]] || { echo "❌ retokenization renamed ${renamed} paths and edited ${edited} files; expected both > 0" >&2 && exit 1; }
echo "  retokenized diene_dart_lib -> diene_fixture: ${renamed} paths renamed, ${edited} files edited"

(cd "${copy}" && dart pub get) >"${work}/get.log" 2>&1 || { echo "❌ dart pub get failed on the fixture:" >&2 && tail -20 "${work}/get.log" >&2 && exit 1; }
(cd "${copy}/${to_pkg}" && dart analyze --fatal-infos --fatal-warnings) >"${work}/analyze.log" 2>&1 || { echo "❌ dart analyze failed on the fixture:" >&2 && tail -30 "${work}/analyze.log" >&2 && exit 1; }
(cd "${copy}/${to_pkg}" && dart test --reporter=compact) >"${work}/test.log" 2>&1 || { echo "❌ dart test failed on the fixture:" >&2 && tail -30 "${work}/test.log" >&2 && exit 1; }
echo "  dart test: $(grep -oE "[+][0-9]+: All tests passed!" "${work}/test.log" | tail -1)"

echo "✅ retokenization-fixture: diene_fixture (scratch retokenization of diene_dart_lib) passes dart pub get, dart analyze --fatal-infos --fatal-warnings and dart test"
