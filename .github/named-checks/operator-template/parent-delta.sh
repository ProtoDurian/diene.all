#!/usr/bin/env bash
set -euo pipefail

# The diff from go-base-w-observability's .3 holds only this node's deliverables
# (goal "Deliverables") and the sanctioned removal of the inherited Note/Redis sample:
# this node has one entry point, cmd/manager. Every changed path must be in the ledger
# with the same status (A added, M modified, D deleted), and every ledger entry must
# still be in the diff. This directory is ignored.

ADDED=(
  '.claude/skills/operator-conventions/SKILL.md'
  'adapters/operator/controllers/conditions.go'
  'adapters/operator/controllers/journal_controller.go'
  'adapters/operator/controllers/note_controller.go'
  'adapters/operator/kube/clock.go'
  'adapters/operator/kube/recorder.go'
  'adapters/operator/kube/resources.go'
  'adapters/operator/ledgerstore/minio.go'
  'adapters/operator/metrics/metrics.go'
  'api/v1alpha1/groupversion_info.go'
  'api/v1alpha1/journal_types.go'
  'api/v1alpha1/note_types.go'
  'api/v1alpha1/zz_generated.deepcopy.go'
  'cmd/manager/main.go'
  'docs/domain/operator-conventions.md'
  'infra/root_chart/templates/_helpers.tpl'
  'infra/root_chart/templates/crds/sample.diene.atomi.cloud_journals.yaml'
  'infra/root_chart/templates/crds/sample.diene.atomi.cloud_notes.yaml'
  'infra/root_chart/templates/dashboard.yaml'
  'infra/root_chart/templates/deployment.yaml'
  'infra/root_chart/templates/grafanaalertrulegroup.yaml'
  'infra/root_chart/templates/metric-taxonomy.yaml'
  'infra/root_chart/templates/rbac/role.yaml'
  'infra/root_chart/templates/rbac/rolebinding.yaml'
  'infra/root_chart/templates/rbac/scraper.yaml'
  'infra/root_chart/templates/service.yaml'
  'infra/root_chart/templates/serviceaccount.yaml'
  'infra/root_chart/templates/servicemonitor.yaml'
  'infra/root_chart/values.amphoros.yaml'
  'infra/root_chart/values.lapras.yaml'
  'infra/root_chart/values.pichu.yaml'
  'infra/root_chart/values.pikachu.yaml'
  'infra/root_chart/values.raichu.yaml'
  'internal/operatorruntime/runtime.go'
  'lib/operator/brake/brake.go'
  'lib/operator/ledger/ledger.go'
  'lib/operator/note/note.go'
  'lib/operator/plan/plan.go'
  'lib/operator/reconcile/reconcile.go'
  'probes/hook-operator-architecture.ts'
  'probes/hook-operator-crd-drift.ts'
  'probes/hook-operator-marker-lint.ts'
  'probes/hook-operator-rbac-minimality.ts'
  'probes/k3d-harness-artifact.ts'
  'probes/k3d-install-toy-reconcile.ts'
  'probes/manager-landscape-values.ts'
  'probes/manager-runtime.ts'
  'probes/operator-blast-brake.ts'
  'probes/operator-crd-schema-validation.ts'
  'probes/operator-ledger-semantics.ts'
  'probes/operator-multi-controller-wiring.ts'
  'probes/operator-observability-artifacts.ts'
  'probes/operator-observe-no-write.ts'
  'probes/operator-reconcile.ts'
  'probes/operator-status-conditions.ts'
  'scripts/local/lib/cluster-name.sh'
  'scripts/local/lib/cluster-name.test.sh'
  'scripts/local/operator-e2e.sh'
  'scripts/local/operator-manifests.sh'
  'scripts/validate/operator-architecture.sh'
  'scripts/validate/operator-crd-drift.sh'
  'scripts/validate/operator-markers.sh'
  'scripts/validate/operator-observability-artifacts.ts'
  'scripts/validate/operator-rbac.sh'
  'tasks/Taskfile.operator.yaml'
  'tests/fixtures/operator/invalid-note.yaml'
  'tests/fixtures/operator/valid-note.yaml'
  'tests/int/operator/adapter_test.go'
  'tests/int/operator/errors_test.go'
  'tests/int/operator/ledger_minio_test.go'
  'tests/int/operator/ledgerstore_bucket_test.go'
  'tests/int/operator/manager_runtime_test.go'
  'tests/int/operator/manager_wiring_test.go'
  'tests/int/operator/reconcile_test.go'
  'tests/int/operator/suite_test.go'
  'tests/unit/operator/brake_test.go'
  'tests/unit/operator/ledger_test.go'
  'tests/unit/operator/note_test.go'
  'tests/unit/operator/plan_test.go'
  'tests/unit/operator/reconcile_test.go'
  'tools/archcheck/main.go'
)

MODIFIED=(
  '.config/go-base.coverage.yaml'
  '.github/workflows/cd.yaml'
  '.github/workflows/ci.yaml'
  '.gitignore'
  '.golangci.yaml'
  'CLAUDE.md'
  'README.md'
  'Taskfile.yaml'
  'docs/developer/go-baseline.md'
  'docs/domain/README.md'
  'docs/standards/docker/index.md'
  'go.mod'
  'go.sum'
  'infra/Dockerfile'
  'infra/root_chart/Chart.yaml'
  'infra/root_chart/README.md'
  'infra/root_chart/values.yaml'
  'nix/env.nix'
  'nix/packages.nix'
  'nix/pre-commit.nix'
  'nix/shells.nix'
  'probes/binary-smoke.ts'
  'probes/build-artifact.ts'
  'probes/docker-build.ts'
  'probes/features.json'
  'probes/helm-render.ts'
  'probes/hook-go-black-box.ts'
  'probes/hook-golangci-lint.ts'
  'probes/integration-tests.ts'
  'probes/lib/go.ts'
  'probes/unit-tests.ts'
  'scripts/ci/helm.sh'
  'scripts/local/build.sh'
  'tasks/Taskfile.docker.yaml'
  'tasks/Taskfile.helm.yaml'
  'tests/sit/cli/cli_test.go'
)

DELETED=(
  'adapters/kv/redis.go'
  'cmd/go-base/main.go'
  'infra/root_chart/templates/configmap.yaml'
  'lib/note/key.go'
  'lib/note/service.go'
  'tests/int/kv/redis_test.go'
  'tests/unit/note/note_test.go'
)

parent_sha="${NAMED_CHECKS_PARENT_SHA:-$(cat "$(dirname "$0")/parent.sha")}"
git rev-parse --verify --quiet "${parent_sha}^{commit}" >/dev/null || git fetch --quiet --no-tags origin "${parent_sha}" || true
git rev-parse --verify --quiet "${parent_sha}^{commit}" >/dev/null || { echo "❌ go-base-w-observability .3 commit ${parent_sha} not found; fetch it first" >&2 && exit 1; }

cd "$(git rev-parse --show-toplevel)"
self_dir=".github/named-checks/operator-template"
work="$(mktemp -d)"
trap 'rm -rf "${work}"' EXIT

{
  for p in "${ADDED[@]}"; do printf 'A\t%s\n' "${p}"; done
  for p in "${MODIFIED[@]}"; do printf 'M\t%s\n' "${p}"; done
  for p in "${DELETED[@]}"; do printf 'D\t%s\n' "${p}"; done
} | LC_ALL=C sort >"${work}/want"

# index tree == HEAD in CI; keeps local staged mutations visible
tree="$(git write-tree)"
git -c core.quotePath=false diff --no-renames --name-status "${parent_sha}" "${tree}" -- . ":!${self_dir}" |
  LC_ALL=C sort >"${work}/got"

duplicates="$(cut -f2 "${work}/want" | LC_ALL=C sort | uniq -d)"
if [[ -n ${duplicates} ]]; then
  echo "❌ ledger lists a path twice: $(tr '\n' ' ' <<<"${duplicates}")" >&2
  exit 1
fi

if ! cmp -s "${work}/want" "${work}/got"; then
  echo "❌ the diff from go-base-w-observability .3 ${parent_sha} is not exactly the ledger:" >&2
  echo "   only in the diff (undeclared change):" >&2
  LC_ALL=C comm -13 "${work}/want" "${work}/got" | sed 's/^/     /' >&2
  echo "   only in the ledger (stale entry or wrong status):" >&2
  LC_ALL=C comm -23 "${work}/want" "${work}/got" | sed 's/^/     /' >&2
  exit 1
fi

echo "✅ parent-delta: the diff from ${parent_sha} is exactly the ${#ADDED[@]} added, ${#MODIFIED[@]} modified and ${#DELETED[@]} deleted ledger paths"
