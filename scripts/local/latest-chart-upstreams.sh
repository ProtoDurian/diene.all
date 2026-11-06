#!/usr/bin/env bash
set -euo pipefail

chart_tags="$(skopeo list-tags docker://quay.io/jetstack/charts/cert-manager | jq -r '.Tags[]' | { rg '^v[0-9]+\.[0-9]+\.[0-9]+$' || true; } | sort -V | tail -n 1)"
image_tags="$(skopeo list-tags docker://quay.io/jetstack/cert-manager-controller | jq -r '.Tags[]' | { rg '^v[0-9]+\.[0-9]+\.[0-9]+$' || true; } | sort -V | tail -n 1)"

[ -z "${chart_tags}" ] && echo "❌ no cert-manager chart tags resolved" >&2 && exit 1
[ -z "${image_tags}" ] && echo "❌ no cert-manager image tags resolved" >&2 && exit 1

echo "📦 latest chart tag: ${chart_tags}"
echo "📦 latest image tag: ${image_tags}"
echo "✅ Upstream tags resolved"
