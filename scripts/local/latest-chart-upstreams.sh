#!/usr/bin/env bash
set -euo pipefail

chart_tags="$(skopeo list-tags docker://ghcr.io/external-secrets/charts/external-secrets | jq -r '.Tags[]' | { rg '^[0-9]+\.[0-9]+\.[0-9]+$' || true; } | sort -V | tail -n 1)"
image_tags="$(skopeo list-tags docker://ghcr.io/external-secrets/external-secrets | jq -r '.Tags[]' | { rg '^v[0-9]+\.[0-9]+\.[0-9]+$' || true; } | sort -V | tail -n 1)"

[ -z "${chart_tags}" ] && echo "❌ no external-secrets chart tags resolved" >&2 && exit 1
[ -z "${image_tags}" ] && echo "❌ no external-secrets image tags resolved" >&2 && exit 1

echo "📦 latest chart tag: ${chart_tags}"
echo "📦 latest image tag: ${image_tags}"
echo "✅ Upstream tags resolved"
