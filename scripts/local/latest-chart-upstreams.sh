#!/usr/bin/env bash
set -euo pipefail

semver() { jq -r '.Tags[]' | { rg '^v2\.[0-9]+\.[0-9]+$' || true; } | sort -V | tail -n 1; }

chart_tags="$(skopeo list-tags docker://cr.kgateway.dev/kgateway-dev/charts/kgateway | semver)"
crds_tags="$(skopeo list-tags docker://cr.kgateway.dev/kgateway-dev/charts/kgateway-crds | semver)"
image_tags="$(skopeo list-tags docker://cr.kgateway.dev/kgateway-dev/kgateway | semver)"
proxy_tags="$(skopeo list-tags docker://cr.kgateway.dev/kgateway-dev/envoy-wrapper | semver)"

[ -z "${chart_tags}" ] && echo "❌ no kgateway chart tags resolved" >&2 && exit 1
[ -z "${crds_tags}" ] && echo "❌ no kgateway-crds chart tags resolved" >&2 && exit 1
[ -z "${image_tags}" ] && echo "❌ no kgateway image tags resolved" >&2 && exit 1
[ -z "${proxy_tags}" ] && echo "❌ no envoy-wrapper image tags resolved" >&2 && exit 1

echo "📦 latest chart tag: ${chart_tags}"
echo "📦 latest crds chart tag: ${crds_tags}"
echo "📦 latest image tag: ${image_tags}"
echo "📦 latest proxy image tag: ${proxy_tags}"
echo "📌 pinned chart: $(yq -r '.dependencies[] | select(.name == "kgateway") | .version' chart/Chart.yaml)"
echo "✅ Upstream tags resolved"
