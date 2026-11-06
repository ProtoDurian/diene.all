#!/usr/bin/env bash
set -euo pipefail

chart_tags="$(skopeo list-tags docker://ghcr.io/grafana/helm-charts/k8s-monitoring | jq -r '.Tags[]' | sort -V | tail -n 1)"
image_tags="$(skopeo list-tags docker://docker.io/grafana/alloy | jq -r '.Tags[]' | { rg '^v[0-9]+\.[0-9]+\.[0-9]+$' || true; } | sort -V | tail -n 1)"

[ -z "${chart_tags}" ] && echo "❌ no k8s-monitoring chart tags resolved" >&2 && exit 1
[ -z "${image_tags}" ] && echo "❌ no Alloy image tags resolved" >&2 && exit 1

echo "📦 latest chart tag: ${chart_tags}"
echo "📦 latest image tag: ${image_tags}"
echo "✅ Upstream tags resolved"
