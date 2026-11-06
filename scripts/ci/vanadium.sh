#!/usr/bin/env bash
set -euo pipefail

for mode in schema schema-drift lint render lpsm-labels names parity rendered-manifests conformance audit-enforce exemption publish-git publish-oci version; do
  bash ./scripts/validate/vanadium.sh "${mode}"
done
bash ./scripts/validate/release-lint.sh parse
bash ./scripts/validate/release-lint.sh vocabulary
bash ./scripts/validate/release-lint.sh types

echo "✅ vanadium unit tier complete"
