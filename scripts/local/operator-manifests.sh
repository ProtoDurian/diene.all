#!/usr/bin/env bash
set -euo pipefail

crd_dir="infra/root_chart/templates/crds"
rbac_dir="infra/root_chart/templates/rbac"
mkdir -p "${crd_dir}" "${rbac_dir}"

controller-gen object paths=./api/...
controller-gen crd paths=./api/... output:crd:dir="${crd_dir}"
controller-gen rbac:roleName=operator-template-manager \
  paths=./adapters/operator/controllers/... output:rbac:dir="${rbac_dir}"

echo "✅ operator manifests generated"
