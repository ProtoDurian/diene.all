#!/usr/bin/env bash
set -euo pipefail

for mode in schema schema-drift lint render toggle-map kube-floor lpsm-labels reloader rendered-manifests pin task-surface publish-git publish-oci version presence; do
  bash ./scripts/validate/xenon.sh "${mode}"
done
bash ./scripts/validate/release-lint.sh parse
bash ./scripts/validate/release-lint.sh vocabulary
bash ./scripts/validate/release-lint.sh types

echo "✅ xenon unit tier complete"
