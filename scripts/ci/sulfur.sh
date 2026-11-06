#!/usr/bin/env bash
set -euo pipefail

for mode in schema schema-drift lint render gateway-api dead-flag issuer-boundary crd-lifecycle sequential-minor lpsm-labels reloader rendered-manifests pin publish-git publish-oci version presence; do
  bash ./scripts/validate/sulfur.sh "${mode}"
done
bash ./scripts/validate/release-lint.sh parse
bash ./scripts/validate/release-lint.sh vocabulary
bash ./scripts/validate/release-lint.sh types

echo "✅ sulfur unit tier complete"
