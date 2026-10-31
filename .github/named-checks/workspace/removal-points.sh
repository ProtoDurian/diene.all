#!/usr/bin/env bash
set -euo pipefail

# For D, H and D+H: strip a copy of the tree per this ledger, then assert the copy is
# valid and no file in it still references a removed path.

D_PATHS=(
  infra/Dockerfile
  .dockerignore
  '.github/workflows/⚡reusable-docker.yaml'
  tasks/Taskfile.docker.yaml
  scripts/ci/docker.sh
  .claude/skills/docker-push
  docs/standards/docker
  probes/docker-build.ts
)
D_TOKENS=(
  infra/Dockerfile .dockerignore reusable-docker Taskfile.docker docker.sh
  docker-push standards/docker docker/index.md docker-build
)

H_PATHS=(
  infra/root_chart
  '.github/workflows/⚡reusable-helm.yaml'
  tasks/Taskfile.helm.yaml
  scripts/ci/helm.sh
  .claude/skills/helm-push
  docs/standards/helm
  probes/helm-lint.ts
  probes/helm-render.ts
  probes/hook-helm-lint.ts
)
H_TOKENS=(
  root_chart reusable-helm Taskfile.helm helm.sh helm-push standards/helm
  helm/index.md a-helm-lint helm-lint helm-render
)

DH_PATHS=(infra .github/workflows/cd.yaml)
DH_TOKENS=('](infra)' 'infra/' workflows/cd.yaml)

SCAN_EXEMPT=('!.github/named-checks/**' '!Changelog.md' '!probes/lib/**')

root="$(git rev-parse --show-toplevel)"
work="$(mktemp -d)"
trap 'rm -rf "${work}"' EXIT
failed=0

fail() {
  echo "❌ $*" >&2
  failed=1
}

rm_paths() {
  local p
  for p in "$@"; do
    if [[ -e ${p} ]]; then rm -rf -- "${p}"; else fail "ledger path ${p} not in tree (stale anchor)"; fi
  done
}

edit() {
  local file="$1"
  shift
  if [[ ! -f ${file} ]]; then
    fail "ledger file ${file} not in tree (stale anchor)"
    return
  fi
  cp -- "${file}" "${work}/before"
  "$@" "${file}" || {
    fail "edit failed on ${file}: ${*}"
    return
  }
  if cmp -s -- "${work}/before" "${file}"; then fail "anchor not found in ${file}: ${*}"; fi
}

yq_del() { yq -i "$1" "$2"; }
sed_z() { sed -i -z "$1" "$2"; }
sed_d() { sed -i "$1" "$2"; }
drop_section() { awk -v h="$1" '$0 == h { skip = 1; next } /^# / { skip = 0 } !skip' "$2" >"${2}.new" && mv "${2}.new" "$2"; }
drop_nix_block() { awk -v s="$1" '$0 == s { skip = 1 } skip { if ($0 ~ /^    };$/) { skip = 0; eat = 1 } next } eat && $0 == "" { eat = 0; next } { eat = 0; print }' "$2" >"${2}.new" && mv "${2}.new" "$2"; }

apply_D() {
  rm_paths "${D_PATHS[@]}"
  edit .github/workflows/ci.yaml yq_del 'del(.jobs.docker)'
  edit .github/workflows/cd.yaml yq_del 'del(.jobs.docker)'
  edit Taskfile.yaml yq_del 'del(.includes.docker)'
  edit .github/dependabot.yml yq_del 'del(.updates[] | select(.package-ecosystem == "docker"))'
  edit dlint.yaml yq_del 'del(.checks["toolchain-smoke"].binaries[] | select(. == "docker" or . == "hadolint"))'
  edit CLAUDE.md drop_section '# Docker build and publishing'
  edit probes/features.json yq_del 'del(.[] | select(.name == "docker-build"))'
  edit probes/binary-smoke.ts sed_d '/^docker --version/d;/^docker info/d;/^hadolint/d'
}

apply_H() {
  rm_paths "${H_PATHS[@]}"
  edit .github/workflows/ci.yaml yq_del 'del(.jobs.helm)'
  edit .github/workflows/cd.yaml yq_del 'del(.jobs.helm)'
  edit Taskfile.yaml yq_del 'del(.includes.helm)'
  edit .github/dependabot.yml yq_del 'del(.updates[] | select(.package-ecosystem == "helm"))'
  edit dlint.yaml yq_del 'del(.checks["toolchain-smoke"].binaries[] | select(. == "helm version" or . == "helm-docs" or . == "kubeconform -v" or . == "kyverno version"))'
  edit CLAUDE.md drop_section '# Helm charts and publishing'
  edit probes/features.json yq_del 'del(.[] | select(.name == "helm-lint" or .name == "helm-render" or .name == "hook-helm-lint"))'
  edit probes/binary-smoke.ts sed_d '/^helm-docs/d;/^helm version/d;/^helm template/d'
  edit nix/pre-commit.nix drop_nix_block '    a-helm-lint = {'
  edit nix/pre-commit.nix sed_d '/"\^infra\/root_chart\/"/d'
  edit nix/fmt.nix sed_d '/"infra\/root_chart\/\*\*"/d'
  edit .gitignore sed_z 's|^### helm\ninfra/root_chart/uploads/\n\n||'
}

apply_set_edits() {
  local axes="$1" doc=docs/standards/taskfile/index.md
  case "${axes}" in
  D) edit "${doc}" sed_z 's#Docker and Helm tasks are keyed by the artifact they act on — one task set per\nDockerfile and per chart. See \[the Docker standard\](\.\./docker/index\.md) and\n\[the Helm standard\](\.\./helm/index\.md) for that naming convention\.#Helm tasks are keyed by the artifact they act on — one task set per chart. See\n[the Helm standard](../helm/index.md) for that naming convention.#' ;;
  H) edit "${doc}" sed_z 's#Docker and Helm tasks are keyed by the artifact they act on — one task set per\nDockerfile and per chart. See \[the Docker standard\](\.\./docker/index\.md) and\n\[the Helm standard\](\.\./helm/index\.md) for that naming convention\.#Docker tasks are keyed by the artifact they act on — one task set per Dockerfile.\nSee [the Docker standard](../docker/index.md) for that naming convention.#' ;;
  DH)
    edit "${doc}" sed_z 's#Docker and Helm tasks are keyed by the artifact they act on — one task set per\nDockerfile and per chart. See \[the Docker standard\](\.\./docker/index\.md) and\n\[the Helm standard\](\.\./helm/index\.md) for that naming convention\.\n\n##'
    rm_paths "${DH_PATHS[@]}"
    edit dlint.yaml yq_del 'del(.checks["ci-wiring"].orchestrators[] | select(. == ".github/workflows/cd.yaml"))'
    # shellcheck disable=SC2016
    edit README.md sed_z 's#declared in \[`Taskfile.yaml`\](Taskfile.yaml), whose `includes:` block maps each\nnamespace to a file under \[`tasks/`\](tasks); a task shown as `<namespace>:<task>`\nis that key in the included file. Build artifacts — Dockerfiles and Helm charts —\nlive under \[`infra/`\](infra) and may be plural, so their tasks are keyed per\nartifact\. See#declared in [`Taskfile.yaml`](Taskfile.yaml). See#'
    edit Taskfile.yaml yq_del 'del(.includes)'
    rmdir tasks
    # shellcheck disable=SC2016
    edit docs/standards/service-tree/index.md sed_z 's#; the published artifact names this repository uses are the\n`with:` inputs on the Docker and Helm caller jobs in `\.github/workflows/ci\.yaml` and\n`\.github/workflows/cd\.yaml`\.#.#'
    ;;
  esac
}

assert_valid() {
  local axes="$1" f tokens=() hits link target dir

  while IFS= read -r f; do
    yq e '.' "${f}" >/dev/null 2>&1 || fail "[${axes}] ${f} is not valid YAML"
  done < <(find . \( -name '*.yaml' -o -name '*.yml' \) -not -path './infra/root_chart/templates/*' | sort)
  while IFS= read -r f; do
    jq -e . "${f}" >/dev/null 2>&1 || fail "[${axes}] ${f} is not valid JSON"
  done < <(find . -name '*.json' | sort)

  if compgen -G '.github/workflows/*.y*ml' >/dev/null; then
    actionlint -config-file .github/actionlint.yaml .github/workflows/*.y*ml >"${work}/actionlint.out" 2>&1 || fail "[${axes}] actionlint failed: $(head -5 "${work}/actionlint.out")"
  fi

  task --list-all >"${work}/task.out" 2>&1 || fail "[${axes}] task --list-all failed: $(head -5 "${work}/task.out")"

  while IFS= read -r f; do
    nix-instantiate --parse "${f}" >/dev/null 2>"${work}/nix.out" || fail "[${axes}] ${f} does not parse: $(head -3 "${work}/nix.out")"
  done < <(find . -name '*.nix' | sort)

  case "${axes}" in
  D) tokens=("${D_TOKENS[@]}") ;;
  H) tokens=("${H_TOKENS[@]}") ;;
  DH) tokens=("${D_TOKENS[@]}" "${H_TOKENS[@]}" "${DH_TOKENS[@]}") ;;
  esac
  local args=(--hidden --no-ignore --line-number --fixed-strings)
  local g t
  for g in "${SCAN_EXEMPT[@]}"; do args+=(--glob "${g}"); done
  for t in "${tokens[@]}"; do args+=(-e "${t}"); done
  hits="$(rg "${args[@]}" . || true)"
  [[ -z ${hits} ]] || fail "[${axes}] files still reference removed paths:"$'\n'"${hits}"

  while IFS= read -r link; do
    f="${link%%:*}"
    target="${link#*:}"
    target="${target#*](}"
    target="${target%)}"
    case "${target}" in http* | '#'* | mailto:*) continue ;; esac
    target="${target%%#*}"
    [[ -z ${target} ]] && continue
    dir="$(dirname "${f}")"
    [[ -e "${dir}/${target}" ]] || fail "[${axes}] ${f} links to missing ${target}"
  done < <(rg --hidden --no-ignore --only-matching --no-line-number --glob '*.md' '\]\([^)]+\)' . | sed 's#^\./##')
}

tree="$(git -C "${root}" write-tree)"
for axes in D H DH; do
  copy="${work}/copy-${axes}"
  mkdir -p "${copy}"
  git -C "${root}" archive "${tree}" | tar -x -C "${copy}"
  if (
    cd "${copy}"
    failed=0
    [[ ${axes} == *D* ]] && apply_D
    [[ ${axes} == *H* ]] && apply_H
    apply_set_edits "${axes}"
    assert_valid "${axes}"
    exit "${failed}"
  ); then
    echo "strip ${axes}: clean and valid"
  else
    failed=1
  fi
done

[[ ${failed} -eq 0 ]]
