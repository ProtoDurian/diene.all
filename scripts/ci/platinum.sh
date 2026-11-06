#!/usr/bin/env bash
set -euo pipefail

for mode in schema schema-drift lint render lpsm-labels fullname gateway health lb entei issuer-free pins reloader rendered-manifests publish-git publish-oci publish-https-dep version task-surface presence; do
  bash ./scripts/validate/platinum.sh "${mode}"
done
bash ./scripts/validate/release-lint.sh parse
bash ./scripts/validate/release-lint.sh vocabulary
bash ./scripts/validate/release-lint.sh types

echo "✅ platinum unit tier complete"
