#!/usr/bin/env bash
set -euo pipefail

version="${1:-}"
[ -z "${version}" ] && echo "❌ version argument not set" >&2 && exit 1

root_dir="${PACKAGE_ROOT:-$(git rev-parse --show-toplevel)}"
pubspec="${root_dir}/packages/diene_dart_lib/pubspec.yaml"
[ -z "${PACKAGE_ROOT:-}" ] && git -C "${root_dir}" restore --source=HEAD -- packages/diene_dart_lib/pubspec.yaml
[ -z "$(yq -r '.version // ""' "${pubspec}")" ] && echo "❌ ${pubspec} must declare a version" >&2 && exit 1

yq -i ".version = \"${version#v}\"" "${pubspec}"

echo "✅ packages/diene_dart_lib/pubspec.yaml stamped to ${version#v}"
