#!/usr/bin/env bash
set -euo pipefail

root_dir="$(git rev-parse --show-toplevel)"
cd "${root_dir}"

member_dir="packages/diene_dart_lib"
member_pubspec="${member_dir}/pubspec.yaml"

[[ -f ${member_pubspec} ]] || {
  echo "❌ member pubspec is missing: ${member_pubspec}" >&2
  exit 1
}

[[ $(yq -r '.name' "${member_pubspec}") != "diene_dart_lib" ]] && echo "❌ member pubspec name must be diene_dart_lib" >&2 && exit 1
[[ $(yq -r '.repository' "${member_pubspec}") != "https://github.com/ProtoDurian/diene.dart_lib" ]] && echo "❌ member pubspec repository is not the snaked mirror" >&2 && exit 1

runtime_deps="$(yq -r '.dependencies // {} | length' "${member_pubspec}")"
[[ ${runtime_deps} -ne 0 ]] && echo "❌ diene_dart_lib must have zero runtime dependencies (found ${runtime_deps})" >&2 && exit 1

if ! yq -r '.workspace[]' pubspec.yaml | grep -qx "packages/diene_dart_lib"; then
  echo "❌ root pubspec.yaml .workspace must list packages/diene_dart_lib" >&2
  exit 1
fi
[[ $(yq -r '.resolution' "${member_pubspec}") != "workspace" ]] && echo "❌ member pubspec must set resolution: workspace" >&2 && exit 1

for file in \
  "${member_dir}/lib/diene_dart_lib.dart" \
  "${member_dir}/lib/test_helper.dart" \
  "${member_dir}/doc/diene_dart_lib.md" \
  "${member_dir}/skills/diene-dart-lib-usage/SKILL.md" \
  "${member_dir}/LICENSE" \
  "${member_dir}/README.md" \
  "${member_dir}/CHANGELOG.md"; do
  [[ -f ${file} ]] || {
    echo "❌ required package artifact is missing: ${file}" >&2
    exit 1
  }
done

if rg -n "package:(test|matcher|mockito|mocktail)/" "${member_dir}/lib/test_helper.dart"; then
  echo "❌ TestHelper must not depend on a test framework or mocking package" >&2
  exit 1
fi

echo "✅ Dart package identity, workspace wiring, artifacts, and TestHelper boundary conform"
