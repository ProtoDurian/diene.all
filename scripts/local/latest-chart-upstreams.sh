#!/usr/bin/env bash
set -euo pipefail

chart_tags="$(curl -fsSL https://kubernetes-sigs.github.io/metrics-server/index.yaml | yq -r '.entries.metrics-server[].version' | { rg '^[0-9]+\.[0-9]+\.[0-9]+$' || true; } | sort -V | tail -n 1)"
image_tags="$(skopeo list-tags docker://registry.k8s.io/metrics-server/metrics-server | jq -r '.Tags[]' | { rg '^v[0-9]+\.[0-9]+\.[0-9]+$' || true; } | sort -V | tail -n 1)"

[ -z "${chart_tags}" ] && echo "❌ no metrics-server chart tags resolved" >&2 && exit 1
[ -z "${image_tags}" ] && echo "❌ no metrics-server image tags resolved" >&2 && exit 1

echo "📦 latest chart tag: ${chart_tags}"
echo "📦 latest image tag: ${image_tags}"
echo "✅ Upstream tags resolved"
