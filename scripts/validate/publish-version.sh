#!/usr/bin/env bash
set -euo pipefail

root_dir="${PACKAGE_ROOT:-$(git rev-parse --show-toplevel)}"
member_pubspec="${root_dir}/packages/diene_e2e/pubspec.yaml"

tag="${1:-${GITHUB_REF_NAME:-}}"

[[ -z ${tag} ]] && echo "❌ provide a v*.*.* tag argument or GITHUB_REF_NAME" >&2 && exit 1
[[ ! ${tag} =~ ^v[0-9]+[.][0-9]+[.][0-9]+([+-][0-9A-Za-z.-]+)?$ ]] && echo "❌ tag must be a semantic v*.*.* version: ${tag}" >&2 && exit 1

manifest_version="$(yq -r '.version' "${member_pubspec}")"
[[ ${manifest_version} != "${tag#v}" ]] && echo "❌ member pubspec.yaml version (${manifest_version}) != tag version (${tag#v})" >&2 && exit 1

echo "✅ member pubspec.yaml matches ${tag}"
