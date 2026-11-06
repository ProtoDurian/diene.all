#!/usr/bin/env bash
set -euo pipefail

for mode in schema schema-drift lint render lpsm-labels reload-stance payload-purity rendered-manifests pin publish-git publish-oci version presence; do
  bash ./scripts/validate/chlorine.sh "${mode}"
done
bash ./scripts/validate/release-lint.sh parse
bash ./scripts/validate/release-lint.sh vocabulary
bash ./scripts/validate/release-lint.sh types

echo "✅ chlorine unit tier complete"
