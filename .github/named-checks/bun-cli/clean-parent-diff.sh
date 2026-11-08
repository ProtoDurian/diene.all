#!/usr/bin/env bash
set -euo pipefail

# The diff from bun-base-wo-helm's .3 commit holds only this node's
# deliverables (goals/bun-cli.md "Deliverables"). Every changed path must be in
# the ledger below with the same status (A added, M modified, D deleted), and
# every ledger entry must still be in the diff (a stale entry fails too). This
# directory is ignored.
#
# LEDGER — read this section to review the node's surface.

ADDED=(
  # entry (composition root)
  bin/bun-cli.ts
  # domain (fenced sample)
  src/lib/kv/doctor-service.ts
  src/lib/kv/interfaces.ts
  src/lib/kv/service.ts
  src/lib/kv/slug.ts
  # adapters
  src/adapters/cli/exit-codes.ts
  src/adapters/kv/api/doctor-controller.ts
  src/adapters/kv/api/get-controller.ts
  src/adapters/kv/api/seed-controller.ts
  src/adapters/kv/api/set-controller.ts
  src/adapters/kv/api/validator.ts
  src/adapters/kv/data/redis-kv-store.ts
  src/adapters/system/shell.ts
  src/adapters/terminal/console-io.ts
  src/adapters/terminal/progress.ts
  src/adapters/terminal/prompt.ts
  src/adapters/terminal/spinner.ts
  # tests
  bunfig.sit.toml
  tests/helpers/fakes.ts
  tests/integration/controller-registration.test.ts
  tests/integration/controllers-real-redis.test.ts
  tests/integration/doctor-controller.test.ts
  tests/integration/get-controller.test.ts
  tests/integration/redis-kv-store-offline.test.ts
  tests/integration/seed-controller.test.ts
  tests/integration/set-controller.test.ts
  tests/integration/terminal-adapters.test.ts
  tests/sit/cli.sit.test.ts
  tests/sit/driver.ts
  tests/unit/install-contract.test.ts
  tests/unit/kv/doctor-service.test.ts
  tests/unit/kv/service.test.ts
  # the slug helper moves with the kv domain; the parent dropped its own copy
  tests/unit/slug.test.ts
  # goreleaser
  .goreleaser.yaml
  go.mod
  goreleaser.go
  # release scripts
  scripts/release/backup-changelog.sh
  scripts/release/compile.sh
  scripts/release/fury.sh
  scripts/release/goreleaser-shim.sh
  scripts/release/install.sh
  scripts/release/publish.sh
  scripts/release/smoke.sh
  # tasks/workflows and their CI entrypoints
  tasks/Taskfile.compile.yaml
  '.github/workflows/⚡reusable-compile.yaml'
  '.github/workflows/⚡reusable-goreleaser.yaml'
  '.github/workflows/⚡reusable-sit.yaml'
  '.github/workflows/⚡reusable-smoke.yaml'
  scripts/ci/compile.sh
  scripts/ci/publish.sh
  scripts/ci/smoke.sh
  # docs/misc
  INSTALLATION.md
  Changelog.old.md
  # probes (chain-side) and the static contracts they drive
  probes/cli-adapter-integration-seam.ts
  probes/cli-adapter-unit-seam.ts
  probes/cli-architecture.ts
  probes/cli-binary-answers.ts
  probes/cli-changelog-asset.ts
  probes/cli-compile.ts
  probes/cli-container-execution.ts
  probes/cli-distroless-base.ts
  probes/cli-docker-release-wiring.ts
  probes/cli-fury-wiring.ts
  probes/cli-goreleaser-check.ts
  probes/cli-goreleaser-snapshot.ts
  probes/cli-homebrew-cask.ts
  probes/cli-installation-parity.ts
  probes/cli-installer-checksum.ts
  probes/cli-installer-platform-guard.ts
  probes/cli-installer-supported.ts
  probes/cli-installer-timeouts.ts
  probes/cli-nfpms-formats.ts
  probes/cli-nix-package.ts
  probes/cli-nix-release-wiring.ts
  probes/cli-nonroot.ts
  probes/cli-platform-smoke.ts
  probes/cli-probe-inventory.ts
  probes/cli-release-artifacts.ts
  probes/cli-release-backup-order.ts
  probes/cli-sit-coverage.ts
  probes/cli-sit-journeys.ts
  probes/cli-version-stamped.ts
  probes/lib/cli-contract.ts
  scripts/validate/cli-contracts.sh
)

MODIFIED=(
  # goal "modifies"
  package.json
  bun.lock
  Taskfile.yaml
  release.yaml
  infra/Dockerfile
  knip.json
  knip.llm.json
  knip.production.json
  knip.production.llm.json
  scripts/ci/test.sh
  nix/packages.nix
  nix/env.nix
  .gitignore
  .github/workflows/ci.yaml
  .github/workflows/cd.yaml
  # the single entry moves from src/index.ts to bin/ (M35: knip/coverage/docs in the same change)
  biome.json
  tsconfig.json
  bunfig.int.toml
  bunfig.unit.toml
  scripts/local/build.sh
  README.md
  docs/developer/bun-baseline.md
  # release variant: release.github false + beforeWrite backup (documented beside the base policy)
  docs/standards/semantic-release/index.md
  # inherited probes retargeted from src/index.ts to the bin entry
  probes/bun-build.ts
  probes/bun-integration-coverage.ts
  probes/bun-preview.ts
  probes/bun-run.ts
  probes/bun-unit-coverage.ts
  probes/features.json
  # the store test follows the adapter into kv/data
  tests/integration/redis-kv-store.test.ts
  # sit joins the tier list scripts/ci/test.sh reads
  .config/bun-base.coverage.yaml
  # the compile output joins the shared clean script
  scripts/local/clean.sh
  # owner !A78/!A84: buildBunCli comes from atomipkgs.lib (flake input passed to
  # nix/packages.nix; the lock floats atomipkgs v5 to the release that ships it)
  flake.nix
  flake.lock
  # toolchain smoke declares the release tools the dev group adds
  dlint.yaml
)

DELETED=(
  # sanctioned fenced swap: the bun-base sample and its single-entry glue (M35)
  src/index.ts
  src/adapters/pino-logger.ts
  src/adapters/redis-kv-store.ts
  src/lib/sample/cleanup.ts
  src/lib/sample/config.ts
  src/lib/sample/interfaces.ts
  src/lib/sample/key.ts
  src/lib/sample/service.ts
  src/lib/sample/structures.ts
  tests/integration/pino-logger.test.ts
  tests/unit/cleanup.test.ts
  tests/unit/config.test.ts
  tests/unit/key.test.ts
  tests/unit/service.test.ts
)

parent_sha="${NAMED_CHECKS_PARENT_SHA:-$(cat "$(dirname "$0")/parent.sha")}"
git rev-parse --verify --quiet "${parent_sha}^{commit}" >/dev/null || git fetch --quiet --no-tags origin "${parent_sha}" || true
git rev-parse --verify --quiet "${parent_sha}^{commit}" >/dev/null || { echo "❌ bun-base-wo-helm .3 commit ${parent_sha} not found; fetch it first" >&2 && exit 1; }

cd "$(git rev-parse --show-toplevel)"
self_dir=".github/named-checks/bun-cli"
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

if [[ "$(cut -f2 "${work}/want" | sort | uniq -d)" != "" ]]; then
  echo "❌ ledger lists a path twice: $(cut -f2 "${work}/want" | sort | uniq -d | tr '\n' ' ')" >&2
  exit 1
fi

if ! cmp -s "${work}/want" "${work}/got"; then
  echo "❌ the diff from bun-base-wo-helm .3 ${parent_sha} is not exactly the ledger:" >&2
  echo "   only in the diff (undeclared change):" >&2
  comm -13 "${work}/want" "${work}/got" | sed 's/^/     /' >&2
  echo "   only in the ledger (stale entry or wrong status):" >&2
  comm -23 "${work}/want" "${work}/got" | sed 's/^/     /' >&2
  exit 1
fi

echo "✅ clean-parent-diff: the diff from ${parent_sha} is exactly the ${#ADDED[@]} added, ${#MODIFIED[@]} modified and ${#DELETED[@]} deleted ledger paths"
