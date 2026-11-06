#!/usr/bin/env bash
set -euo pipefail

# aseity must not add Docker images, Helm, D1, KV, Queues or Next.js.
# Docker Compose for local dev is allowed (compose.dev.yaml only).

cd "$(git rev-parse --show-toplevel)"
# index tree == HEAD in CI; keeps local staged mutations visible
tree="$(git write-tree)"
failed=0

fail() {
  echo "❌ $*" >&2
  failed=1
}

paths="$(git -c core.quotePath=false ls-tree -r --name-only "${tree}")"
forbidden="$(grep -E '(^|/)(Dockerfile(\..*)?|\.dockerignore|Chart\.yaml|values\.yaml|next\.config\.[cm]?[jt]s)$|^\.github/workflows/.*(docker|helm)|^tasks/Taskfile\.(docker|helm)\.yaml$|^scripts/ci/(docker|helm)\.sh$' <<<"${paths}" | grep -v '^\.github/named-checks/' || true)"
[[ -z ${forbidden} ]] || fail "forbidden files tracked:"$'\n'"${forbidden}"

compose="$(grep -E '(^|/)(docker-)?compose(\.[a-z0-9-]+)?\.ya?ml$' <<<"${paths}" | grep -v '^compose\.dev\.yaml$' || true)"
[[ -z ${compose} ]] || fail "only compose.dev.yaml may hold a compose stack:"$'\n'"${compose}"
if git cat-file -e "${tree}:compose.dev.yaml" 2>/dev/null; then
  [[ "$(git show "${tree}:compose.dev.yaml" | yq '[.services[] | select(has("build"))] | length')" == 0 ]] || fail "compose.dev.yaml builds an image"
fi

pkg="$(git show "${tree}:package.json")"
[[ "$(jq '[(.dependencies // {}), (.devDependencies // {}) | keys[] | select(test("^(next|@cloudflare/next-on-pages|@opennextjs/.*)$"))] | length' <<<"${pkg}")" == 0 ]] || fail "package.json depends on Next.js"

if git cat-file -e "${tree}:wrangler.jsonc" 2>/dev/null; then
  hits="$(git show "${tree}:wrangler.jsonc" | grep -n -E '"(d1_databases|kv_namespaces|queues)"' || true)"
  [[ -z ${hits} ]] || fail "wrangler.jsonc declares D1, KV or Queues:"$'\n'"${hits}"
fi

pushes="$(git -c core.quotePath=false grep -n -E 'docker (build|push)|docker/build-push-action|helm (install|upgrade|package|push)' "${tree}" -- . ':!.github/named-checks/**' ':!Changelog.md' ':!probes/lib/**' || true)"
[[ -z ${pushes} ]] || fail "files build or push an image or chart:"$'\n'"${pushes}"

if [[ ${failed} -ne 0 ]]; then
  exit 1
fi

echo "✅ stack-absence: no Docker image, Helm, D1, KV, Queues or Next.js"
