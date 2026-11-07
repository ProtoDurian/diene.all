#!/usr/bin/env bash
set -euo pipefail

root_dir="$(git rev-parse --show-toplevel)"
cd "${root_dir}"

member_dir="packages/diene_api_engine"
member_pubspec="${member_dir}/pubspec.yaml"

[[ -f ${member_pubspec} ]] || {
  echo "❌ member pubspec is missing: ${member_pubspec}" >&2
  exit 1
}

[[ $(yq -r '.name' "${member_pubspec}") != "diene_api_engine" ]] && echo "❌ member pubspec name must be diene_api_engine" >&2 && exit 1
[[ $(yq -r '.repository' "${member_pubspec}") != "https://github.com/ProtoDurian/diene.dart_api_engine" ]] && echo "❌ member pubspec repository is not the snaked mirror" >&2 && exit 1
[[ $(yq -r '.issue_tracker' "${member_pubspec}") != "https://github.com/ProtoDurian/diene.dart_api_engine/issues" ]] && echo "❌ member pubspec issue_tracker is not the mirror's issues page" >&2 && exit 1
sdk_range='^>=3[.][0-9]+[.][0-9]+ <4[.]0[.]0$'
[[ ! $(yq -r '.environment.sdk // ""' "${member_pubspec}") =~ ${sdk_range} ]] && echo "❌ member pubspec environment.sdk must be a >=3.x.y <4.0.0 range" >&2 && exit 1
[[ $(yq -r '.topics // [] | length' "${member_pubspec}") -lt 1 ]] && echo "❌ member pubspec declares no pub.dev topics" >&2 && exit 1
[[ $(head -n 1 "${member_dir}/LICENSE") != "MIT License" ]] && echo "❌ ${member_dir}/LICENSE is not the MIT license" >&2 && exit 1

runtime_deps="$(yq -r '.dependencies // {} | keys | sort | join(" ")' "${member_pubspec}")"
expected_deps='collection diene_auth_engine diene_problems diene_result dio flutter json_annotation meta retrofit'
[[ ${runtime_deps} != "${expected_deps}" ]] && echo "❌ diene_api_engine runtime dependencies must be exactly: ${expected_deps} (found: ${runtime_deps})" >&2 && exit 1
[[ $(yq -r '.dependencies.flutter.sdk // ""' "${member_pubspec}") != "flutter" ]] && echo "❌ the flutter dependency must be the Flutter SDK" >&2 && exit 1
not_hosted="$(yq -r '.dependencies | to_entries[] | select(.key != "flutter") | select((.value | tag) != "!!str" or (.value | tostring | test("^\^[0-9]+[.][0-9]+[.][0-9]+$") | not)) | .key' "${member_pubspec}")"
[[ -n ${not_hosted} ]] && echo "❌ runtime dependencies must be hosted caret ranges: ${not_hosted//$'\n'/ }" >&2 && exit 1
[[ $(yq -r '.dependency_overrides // {} | length' "${member_pubspec}") -ne 0 ]] && echo "❌ diene_api_engine must not override dependencies" >&2 && exit 1

if ! yq -r '.workspace[]' pubspec.yaml | grep -qx "packages/diene_api_engine"; then
  echo "❌ root pubspec.yaml .workspace must list packages/diene_api_engine" >&2
  exit 1
fi
[[ $(yq -r '.resolution' "${member_pubspec}") != "workspace" ]] && echo "❌ member pubspec must set resolution: workspace" >&2 && exit 1

for file in \
  "${member_dir}/lib/diene_api_engine.dart" \
  "${member_dir}/doc/diene_api_engine.md" \
  "${member_dir}/skills/diene-api-engine-usage/SKILL.md" \
  "${member_dir}/LICENSE" \
  "${member_dir}/README.md" \
  "${member_dir}/CHANGELOG.md"; do
  [[ -f ${file} ]] || {
    echo "❌ required package artifact is missing: ${file}" >&2
    exit 1
  }
done

if [[ -f ${member_dir}/lib/test_helper.dart ]] && rg -n "package:(test|matcher|mockito|mocktail)/" "${member_dir}/lib/test_helper.dart"; then
  echo "❌ TestHelper must not depend on a test framework or mocking package" >&2
  exit 1
fi

echo "✅ Dart package identity, workspace wiring, artifacts, and TestHelper boundary conform"
