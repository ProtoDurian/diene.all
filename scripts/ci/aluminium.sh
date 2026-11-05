#!/usr/bin/env bash
set -euo pipefail

for mode in schema schema-drift lint render topology otlp-contract features-off gigapipe-naming secret otlp-everywhere lpsm-labels rendered-manifests pin publish-git publish-oci version presence; do
  bash ./scripts/validate/aluminium.sh "${mode}"
done
bash ./scripts/validate/release-lint.sh parse
bash ./scripts/validate/release-lint.sh vocabulary
bash ./scripts/validate/release-lint.sh types

echo "✅ aluminium unit tier complete"
