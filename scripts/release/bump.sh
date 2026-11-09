#!/usr/bin/env bash
set -euo pipefail

version="${1:-}"
[ -z "${version}" ] && echo "❌ version argument not set" >&2 && exit 1

# Regenerate chart/README.md too, or a-wrapper-helm-docs fails on the next commit.
yq eval -i ".version = \"${version#v}\"" chart/Chart.yaml
helm-docs --chart-search-root chart

echo "✅ chart manifest and generated chart docs stamped to ${version#v}"
