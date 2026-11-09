#!/usr/bin/env bash
# shellcheck disable=SC2016 # ledger blocks are literal text
set -euo pipefail

# HEAD == shared-wo-docker .3 + new files + the ledger below, byte for byte.
NO_NEW_FILES_UNDER=(nix/ docs/standards/ probes/lib/ .claude/skills/vendor/ .github/named-checks/)
self_dir=.github/named-checks/helm-wrapper

cd "$(git rev-parse --show-toplevel)"
parent_sha="${NAMED_CHECKS_PARENT_SHA:-$(cat "${self_dir}/parent.sha")}"
git rev-parse --verify --quiet "${parent_sha}^{commit}" >/dev/null || git fetch --quiet --no-tags origin "${parent_sha}" || true
git rev-parse --verify --quiet "${parent_sha}^{commit}" >/dev/null || { echo "❌ shared-wo-docker .3 commit ${parent_sha} not found; fetch it first" >&2 && exit 1; }

# index tree == HEAD in CI; keeps local staged mutations visible
tree="$(git write-tree)"
work="$(mktemp -d)"
trap 'rm -rf "${work}"' EXIT
failed=0
fail() {
  echo "❌ $*" >&2
  failed=1
}

LEDGER_FILES=(.github/dependabot.yml .github/workflows/⚡reusable-precommit.yaml scripts/local/setup.sh .github/workflows/cd.yaml .gitignore CLAUDE.md README.md Taskfile.yaml dlint.yaml nix/fmt.nix nix/env.nix nix/packages.nix nix/pre-commit.nix release.yaml probes/binary-smoke.ts)
declare -A LEDGER=()
for f in "${LEDGER_FILES[@]}"; do LEDGER["${f}"]=1; done

# <op> <file> <anchor> <block>: the anchor is an exact whole line and must occur exactly once.
after() { L="$2" B="$3" awk 'BEGIN { n = 0 } { print } $0 == ENVIRON["L"] { n++; printf "%s", ENVIRON["B"] } END { exit n != 1 }' "$1" >"$1.new" && mv "$1.new" "$1"; }
replace() { L="$2" B="$3" awk 'BEGIN { n = 0 } $0 == ENVIRON["L"] { n++; printf "%s", ENVIRON["B"]; next } { print } END { exit n != 1 }' "$1" >"$1.new" && mv "$1.new" "$1"; }
append() { printf '%s' "$2" >>"$1"; }
# before_tail <file> <n> <block>: insert before the file's last n lines.
before_tail() { N="$2" B="$3" awk '{ line[NR] = $0 } END { for (i = 1; i <= NR; i++) { if (i == NR - ENVIRON["N"] + 1) printf "%s", ENVIRON["B"]; print line[i] } }' "$1" >"$1.new" && mv "$1.new" "$1"; }
# squeeze <file>: collapse runs of blank lines left by deleted lines.
squeeze() { cat -s "$1" >"$1.new" && mv "$1.new" "$1"; }

apply_ledger() {
  append .github/dependabot.yml "  - package-ecosystem: helm
    directory: /chart
    schedule:
      interval: weekly
    groups:
      all:
        patterns:
          - '*'
    open-pull-requests-limit: 2
"
  append .github/workflows/cd.yaml '
  chart:
    name: OCI Chart
    permissions:
      contents: read
      packages: write
    uses: ./.github/workflows/⚡reusable-chart-publish.yaml
    secrets: inherit
    with:
      version: ${{ github.ref_name }}
'
  append .gitignore "
### helm-wrapper
chart/files/config/
dist/
probe-report.json
.chart-checks/
"
  append CLAUDE.md '
# Helm wrapper

Read [docs/developer/helm-wrapper-baseline.md](docs/developer/helm-wrapper-baseline.md) before changing `chart/`, the stacked values, CR/LPSM helpers, provider LoadBalancer annotations, config vendoring, or chart publishing.
'
  append README.md '
# Helm wrapper

This branch adds the wrapper chart, stacked values, generated schema, rendered-manifest validation, and dual publish modes.

- `task build` — vendor external config and build pinned chart dependencies.
- `pre-commit run --all-files` — run the three chart-check hooks: helm lint, the values-schema generator, and `chart-checks` on the rendered manifests.
- `task example:lapras:template` — render the independent landscape + cluster stack.
- [Helm wrapper baseline](docs/developer/helm-wrapper-baseline.md)
'
  after Taskfile.yaml "  helm: tasks/Taskfile.helm.yaml" "  example:lapras:
    taskfile: tasks/Taskfile.cluster.yaml
    vars:
      RELEASE_NAME: helm-wrapper
      NAMESPACE: sample
      LANDSCAPE: example
      CLUSTER: lapras
"
  after Taskfile.yaml "      - pre-commit run --all-files" "
  build:
    desc: Vendor config and build chart dependencies
    cmds:
      - ./scripts/local/vendor-chart-config.sh
      - helm dependency build chart

  update:
    desc: Refresh the pinned upstream chart dependency
    cmds:
      - helm dependency update chart

  latest:
    desc: Resolve the latest real upstream chart and image tags
    cmds:
      - ./scripts/local/latest-chart-upstreams.sh
"
  after dlint.yaml "      - helm-docs" "      - helm-schema --help
"
  after dlint.yaml "      - bash" "      - chart-checks --version
"
  replace dlint.yaml "      - k3d" ""
  replace dlint.yaml "      - kubeconform -v" ""
  replace dlint.yaml "      - kyverno version" ""
  after nix/fmt.nix '          "infra/root_chart/**"' '          "chart/**"
          "probes/fixtures/contracts-chart/templates/**"
'
  after nix/env.nix "    dlint" "    helm-schema
"
  after nix/env.nix "    actionlint" "    chart-checks
"
  after nix/packages.nix "          dlint" "          helm-schema
"
  after nix/packages.nix "          atomiutils" "          chart-checks
"
  after nix/pre-commit.nix '        "^infra/root_chart/"' '        "^chart/"
        "^probes/fixtures/contracts-chart/templates/"
'
  before_tail nix/pre-commit.nix 2 '
    a-wrapper-helm-docs = {
      enable = true;
      name = "Helm wrapper docs";
      entry = "${packages.infralint}/bin/helm-docs --chart-search-root chart";
      files = "^chart/.*";
      pass_filenames = false;
      language = "system";
    };

    a-wrapper-helm-lint = {
      enable = true;
      name = "Helm wrapper lint";
      entry = "${packages.atomiutils}/bin/bash -c '"'"'PATH=${envPath}:\$PATH bash scripts/validate/helm-wrapper.sh lint'"'"'";
      files = "^(chart/.*|config/.*|scripts/(local|validate)/.*)$";
      pass_filenames = false;
      language = "system";
    };

    a-wrapper-manifests = {
      enable = true;
      name = "Helm wrapper manifests";
      entry = "${packages.atomiutils}/bin/bash -c '"'"'PATH=${envPath}:\$PATH bash scripts/validate/helm-wrapper.sh manifests'"'"'";
      files = "^(chart/.*|config/.*|chart-checks\\.yaml|scripts/(local|validate)/.*)$";
      pass_filenames = false;
      language = "system";
    };

    # Generator hook: it rewrites chart/values.schema.json in place, so pre-commit goes red when the
    # committed file is stale.
    a-wrapper-values-schema = {
      enable = true;
      name = "Helm wrapper values schema";
      entry = "${packages.atomiutils}/bin/bash -c '"'"'PATH=${envPath}:\$PATH bash scripts/validate/helm-wrapper.sh schema'"'"'";
      files = "^(chart/values\\.yaml|chart/values\\.schema\\.json|scripts/local/generate-chart-schema\\.sh)$";
      pass_filenames = false;
      language = "system";
    };
'
  replace probes/binary-smoke.ts "helm template diene-workspace infra/root_chart | kubeconform -strict -summary >/dev/null" "helm template diene-workspace infra/root_chart >/dev/null

chart-checks --version >/dev/null
"
  replace probes/binary-smoke.ts "k3d version >/dev/null" ""
  replace probes/binary-smoke.ts "k3d cluster list --no-headers >/dev/null" ""
  replace probes/binary-smoke.ts "kubeconform -v >/dev/null" ""
  replace probes/binary-smoke.ts "kyverno version >/dev/null" ""
  replace probes/binary-smoke.ts "printf '%s\n' '{\"probe\":{\"ok\":true}}' | kyverno jp query 'probe.ok' 2>/dev/null | tail -n 1 | rg -qx true" ""
  squeeze probes/binary-smoke.ts
  after scripts/local/setup.sh "skills-sync sync" "chart-checks install
"
  after .github/workflows/⚡reusable-precommit.yaml "      - uses: AtomiCloud/actions.setup-nix@v3" '      - name: Restore chart-checks inputs
        uses: actions/cache@v4
        with:
          path: .chart-checks
          key: chart-checks-${{ hashFiles('"'"'chart-checks.yaml'"'"') }}
'
  after release.yaml "      - docs/developer/CommitConventions.md" "      - chart/Chart.yaml
      - chart/README.md
"
  replace release.yaml "    prepare: []" "    prepare:
      - phase: afterWrite
        command: './scripts/release/bump.sh \${version}'
"
}

copy="${work}/parent"
mkdir -p "${copy}"
git archive "${parent_sha}" | tar -x -C "${copy}"
(
  cd "${copy}"
  for f in "${LEDGER_FILES[@]}"; do
    [[ -f ${f} ]] || {
      echo "❌ ledger file ${f} is not in the parent tree (stale anchor)" >&2
      exit 1
    }
  done
  apply_ledger 2>/dev/null || {
    echo "❌ a ledger anchor no longer occurs exactly once in the parent tree" >&2
    exit 1
  }
) || failed=1

# A registry bump moves only the locked atomipkgs node: every other node and the root inputs stay as in the parent.
lock_ok() {
  local parent_lock head_lock
  parent_lock="$(git show "${parent_sha}:flake.lock" | jq -S -c 'del(.nodes.atomipkgs.locked)')"
  head_lock="$(git show "${tree}:flake.lock" | jq -S -c 'del(.nodes.atomipkgs.locked)')" || return 1
  [[ ${parent_lock} == "${head_lock}" ]]
}

features_ok() {
  local parent_rows head_rows
  parent_rows="$(git show "${parent_sha}:probes/features.json" | jq -c '.')"
  head_rows="$(git show "${tree}:probes/features.json" | jq -c '.')" || return 1
  jq -e -n --argjson p "${parent_rows}" --argjson h "${head_rows}" \
    '($h[0:($p | length)] == $p) and ($h[($p | length):] | length > 0 and all(.[]; .template == "diene/helm-wrapper"))' >/dev/null
}

while IFS=$'\t' read -r status path; do
  case "${status}" in
  A)
    for prefix in "${NO_NEW_FILES_UNDER[@]}"; do
      if [[ ${path} == "${prefix}"* && ${path} != "${self_dir}/"* ]]; then fail "new file in a parent-owned tree: ${path}"; fi
    done
    ;;
  M)
    if [[ ${path} == probes/features.json ]]; then
      features_ok || fail "probes/features.json: parent rows must stay unchanged, followed only by diene/helm-wrapper rows"
    elif [[ ${path} == flake.lock ]]; then
      lock_ok || fail "flake.lock: only the locked atomipkgs node (a registry bump) may differ from the parent"
    elif [[ -z ${LEDGER[${path}]:-} ]]; then
      fail "inherited file changed outside the ledger: ${path}"
    fi
    ;;
  *) fail "${status} ${path}: only new files and ledger edits are allowed" ;;
  esac
done < <(git -c core.quotePath=false diff --name-status --no-renames "${parent_sha}" "${tree}")

for f in "${LEDGER_FILES[@]}"; do
  git show "${tree}:${f}" >"${work}/head" 2>/dev/null || {
    fail "ledger file ${f} missing from HEAD"
    continue
  }
  cmp -s "${copy}/${f}" "${work}/head" || {
    fail "${f} differs from the parent + ledger (left: ledger, right: HEAD):"
    diff -u "${copy}/${f}" "${work}/head" | head -30 >&2 || true
  }
done

self_files="$(git ls-tree --name-only "${tree}" -- "${self_dir}/" | LC_ALL=C sort | tr '\n' ' ')"
expected="${self_dir}/baseline-doc.sh ${self_dir}/branch-ancestry.sh ${self_dir}/docker-absence.sh ${self_dir}/doppler-absence.sh ${self_dir}/exact-diff.sh ${self_dir}/no-vendored-artifacts.sh ${self_dir}/parent.sha "
[[ ${self_files} == "${expected}" ]] || fail "${self_dir} holds files beyond the six checks and parent.sha: ${self_files}"

[[ ${failed} -eq 0 ]] || exit 1
echo "✅ exact-diff: HEAD == shared-wo-docker .3 ${parent_sha} + new files + the ledger"
