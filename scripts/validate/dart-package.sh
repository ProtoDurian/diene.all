#!/usr/bin/env bash
set -euo pipefail

root_dir="$(git rev-parse --show-toplevel)"
cd "${root_dir}"

member_dir="packages/diene_config"
member_pubspec="${member_dir}/pubspec.yaml"

[[ -f ${member_pubspec} ]] || {
  echo "❌ member pubspec is missing: ${member_pubspec}" >&2
  exit 1
}

[[ $(yq -r '.name' "${member_pubspec}") != "diene_config" ]] && echo "❌ member pubspec name must be diene_config" >&2 && exit 1
[[ $(yq -r '.repository' "${member_pubspec}") != "https://github.com/ProtoDurian/diene.dart_config" ]] && echo "❌ member pubspec repository is not the snaked mirror" >&2 && exit 1
[[ $(yq -r '.issue_tracker' "${member_pubspec}") != "https://github.com/ProtoDurian/diene.dart_config/issues" ]] && echo "❌ member pubspec issue_tracker is not the mirror's issues page" >&2 && exit 1
sdk_range='^>=3[.][0-9]+[.][0-9]+ <4[.]0[.]0$'
[[ ! $(yq -r '.environment.sdk // ""' "${member_pubspec}") =~ ${sdk_range} ]] && echo "❌ member pubspec environment.sdk must be a >=3.x.y <4.0.0 range" >&2 && exit 1
[[ $(yq -r '.topics // [] | length' "${member_pubspec}") -lt 1 ]] && echo "❌ member pubspec declares no pub.dev topics" >&2 && exit 1
[[ $(head -n 1 "${member_dir}/LICENSE") != "MIT License" ]] && echo "❌ ${member_dir}/LICENSE is not the MIT license" >&2 && exit 1

runtime_deps="$(yq -r '.dependencies // {} | keys | sort | join(",")' "${member_pubspec}")"
[[ ${runtime_deps} != "diene_core_utils,diene_problems,diene_result,yaml" ]] && echo "❌ diene_config must have exactly four runtime dependencies, diene_core_utils, diene_problems, diene_result and yaml (found '${runtime_deps}')" >&2 && exit 1
caret_range='^\^[0-9]+[.][0-9]+[.][0-9]+$'
for dep in diene_core_utils diene_problems diene_result yaml; do
  [[ $(yq -r ".dependencies.${dep} | tag" "${member_pubspec}") != "!!str" || ! $(yq -r ".dependencies.${dep}" "${member_pubspec}") =~ ${caret_range} ]] && echo "❌ ${dep} must be a hosted pub.dev dependency with a caret range (^x.y.z)" >&2 && exit 1
done

if ! yq -r '.workspace[]' pubspec.yaml | grep -qx "packages/diene_config"; then
  echo "❌ root pubspec.yaml .workspace must list packages/diene_config" >&2
  exit 1
fi
[[ $(yq -r '.resolution' "${member_pubspec}") != "workspace" ]] && echo "❌ member pubspec must set resolution: workspace" >&2 && exit 1

for file in \
  "${member_dir}/lib/diene_config.dart" \
  "${member_dir}/doc/diene_config.md" \
  "${member_dir}/skills/diene-config-usage/SKILL.md" \
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
