#!/usr/bin/env bash
set -euo pipefail

root_dir="$(git rev-parse --show-toplevel)"
cd "${root_dir}"

member_pubspec="packages/diene_e2e/pubspec.yaml"
current_version="$(yq -r '.version' "${member_pubspec}")"

fixture="$(mktemp -d)"
trap 'rm -rf "${fixture}"' EXIT
mkdir -p "${fixture}/packages/diene_e2e"
cp "${member_pubspec}" "${fixture}/${member_pubspec}"

PACKAGE_ROOT="${fixture}" ./scripts/validate/publish-version.sh "v${current_version}"

yq -i '.version = "9.9.9"' "${fixture}/${member_pubspec}"
if PACKAGE_ROOT="${fixture}" ./scripts/validate/publish-version.sh "v${current_version}" 2>/dev/null; then
  echo "❌ publish guard accepted a manifest/tag mismatch" >&2
  exit 1
fi

PACKAGE_ROOT="${fixture}" ./scripts/release/bump.sh v9.8.7
[[ $(yq -r '.version' "${fixture}/${member_pubspec}") != "9.8.7" ]] && echo "❌ bump.sh did not stamp the member pubspec.yaml" >&2 && exit 1

[[ $(yq -r '[.release.commit.assets[] | select(. == "packages/diene_e2e/pubspec.yaml")] | length' release.yaml) != "1" ]] && echo "❌ release.yaml commit.assets must list packages/diene_e2e/pubspec.yaml" >&2 && exit 1
# shellcheck disable=SC2016 # ${version} is the literal releaser placeholder
[[ $(yq -r '[.release.hooks.prepare[] | select(.command == "./scripts/release/bump.sh ${version}")] | length' release.yaml) != "1" ]] && echo '❌ release.yaml must run ./scripts/release/bump.sh ${version} in its prepare hooks' >&2 && exit 1

tag_trigger="$(yq -r '.on.push.tags | join(",")' .github/workflows/cd.yaml)"
[[ ${tag_trigger} != "v[0-9]+.[0-9]+.[0-9]+" ]] && echo "❌ cd.yaml must trigger on exactly the v[0-9]+.[0-9]+.[0-9]+ tag pattern, got '${tag_trigger}'" >&2 && exit 1

echo "✅ release stamping, the manifest/tag guard, release assets and the CD tag trigger conform"
