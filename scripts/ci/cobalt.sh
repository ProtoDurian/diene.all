#!/usr/bin/env bash
set -euo pipefail

for mode in schema schema-drift lint render store-auth store-scope crd-lifecycle v1-only lpsm-labels reloader rendered-manifests pin publish-git publish-oci version presence; do
  bash ./scripts/validate/cobalt.sh "${mode}"
done
bash ./scripts/validate/release-lint.sh parse
bash ./scripts/validate/release-lint.sh vocabulary
bash ./scripts/validate/release-lint.sh types

echo "✅ cobalt unit tier complete"
