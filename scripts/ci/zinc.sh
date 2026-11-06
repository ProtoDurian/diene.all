#!/usr/bin/env bash
set -euo pipefail

for mode in schema schema-drift lint render lpsm-labels secret task-surface directory-map entei-overlay issuer-cardinality no-certificate credential-literal rendered-manifests stale-row publish-git publish-oci version presence; do
  bash ./scripts/validate/zinc.sh "${mode}"
done
bash ./scripts/validate/release-lint.sh parse
bash ./scripts/validate/release-lint.sh vocabulary
bash ./scripts/validate/release-lint.sh types

echo "✅ zinc unit tier complete"
