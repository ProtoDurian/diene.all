#!/usr/bin/env bash
set -euo pipefail

module="$(yq -r '.module' .config/go-lib.yaml)"
mirror="$(yq -r '.mirror' .config/go-lib.yaml)"
user_modcache="$(go env GOMODCACHE)"
upstream_proxy="$(go env GOPROXY)"
tmp="$(mktemp -d)"
trap 'chmod -R u+w "${tmp}" 2>/dev/null || true; rm -rf "${tmp}"' EXIT
source_repo="$(git rev-parse --show-toplevel)"
revision="$(git rev-parse HEAD)"
consumer="${tmp}/consumer"
mkdir -p "${consumer}"

export GOENV=off GOWORK=off GOTOOLCHAIN=local GOFLAGS=-mod=mod GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL="${tmp}/gitconfig"
git config --global protocol.file.allow always
# Background gc rewrites the shallow file under Go's later fetch --unshallow.
git config --global maintenance.auto false
git config --global gc.auto 0
git config --global url."file://${source_repo}".insteadOf "https://github.com/${mirror}"

echo "📦 Packing ${module}@${revision} the way the module proxy does (go mod download from git)..."
packed="$(GOMODCACHE="${tmp}/pack-modcache" GOPROXY=direct GOPRIVATE="${module}" go mod download -json "${module}@${revision}" || true)"
version="$(jq -r '.Version // empty' <<<"${packed}" 2>/dev/null || true)"
dir="$(jq -r '.Dir // empty' <<<"${packed}" 2>/dev/null || true)"
[[ -z ${dir} || ! -d ${dir} ]] && echo "❌ go mod download did not pack ${module}: ${packed}" >&2 && exit 1

# Literal directories, not ./...: a pattern skips directories whose build tags exclude every file.
mapfile -t candidates < <(git ls-files -c -o --exclude-standard -- '*.go' | xargs -r dirname | LC_ALL=C sort -u |
  rg -v -e '(^|/)testdata(/|$)' -e '(^|/)[._][^/]+' | sed -E 's#^([^.])#./\1#')
mapfile -t directories < <(go list -e -f "{{if and .Module (eq .Module.Path \"${module}\")}}{{.ImportPath}}{{end}}" "${candidates[@]}" |
  sed -E "s#^${module}/?##; s#^\$#.#")
template="{{if and .Module (eq .Module.Path \"${module}\")}}"
for field in GoFiles CgoFiles IgnoredGoFiles IgnoredOtherFiles TestGoFiles XTestGoFiles EmbedFiles TestEmbedFiles XTestEmbedFiles; do
  template+="{{range .${field}}}{{\$.ImportPath}}/{{.}}"$'\n'"{{end}}"
done
template+="{{end}}"
manifest() {
  local prefix="$1" directory
  local paths=()
  for directory in "${directories[@]}"; do
    if [[ ${directory} == "." ]]; then paths+=("${prefix}"); else paths+=("${prefix}/${directory}"); fi
  done
  GOFLAGS=-mod=readonly go list -e -f "${template}" "${paths[@]}" | LC_ALL=C sort
}
manifest . >"${tmp}/declared"
mapfile -t packages < <(go list -e -f '{{if and .GoFiles (ne .Name "main")}}{{.ImportPath}}{{end}}' ./... |
  rg -v '(^|/)internal(/|$)' || true)
[[ ${#packages[@]} -eq 0 ]] && echo "❌ ${module} declares no importable package" >&2 && exit 1

echo "📥 Installing the packed ${module}@${version} into a fresh module by local replace..."
cat "${dir}/go.sum" >"${consumer}/go.sum"
{
  printf 'package main\n\nimport (\n'
  for package in "${packages[@]}"; do printf '\t_ "%s"\n' "${package}"; done
  printf ')\n\nfunc main() {}\n'
} >"${consumer}/main.go"
cat >"${consumer}/consumer_test.go" <<GO
package main_test

import (
	"encoding/json"
	"fmt"
	"testing"

	"${module}/lib/problem"
	"${module}/testhelper"
)

func TestPackedLibraryRoundTrip(t *testing.T) {
	registry, err := problem.NewRegistry(testhelper.SampleErrorPortal(), problem.GenericProblems()...)
	if err != nil {
		t.Fatal(err)
	}
	data := map[string]any{"entityType": "user", "id": "42"}
	envelope, err := registry.NewProblem("entity_not_found", data)
	if err != nil {
		t.Fatal(err)
	}
	encoded, err := json.Marshal(envelope)
	if err != nil {
		t.Fatal(err)
	}
	var decoded problem.Problem
	if err := json.Unmarshal(encoded, &decoded); err != nil {
		t.Fatal(err)
	}
	testhelper.AssertError(t, fmt.Errorf("loading user: %w", problem.NewError(decoded)),
		testhelper.ExpectID("entity_not_found"), testhelper.ExpectStatus(404), testhelper.ExpectData(data))
}
GO

(
  cd "${consumer}"
  export GOMODCACHE="${tmp}/modcache" GOPROXY="file://${user_modcache}/cache/download,${upstream_proxy}" GONOSUMDB="${module}"
  go mod init example.invalid/go-lib-consumer 2>"${tmp}/init.log" || {
    cat "${tmp}/init.log" >&2
    exit 1
  }
  go mod edit -require="${module}@v0.0.0-00010101000000-000000000000" -replace="${module}=${dir}"
  go mod tidy
  [[ "$(go list -m -f '{{.Replace.Dir}}' "${module}")" != "${dir}" ]] && echo "❌ ${module} did not resolve to the packed module" >&2 && exit 1

  echo "🔎 Comparing the packed module's files with the package manifest..."
  manifest "${module}" >"${tmp}/packed"
  if ! diff -u --label manifest --label packed "${tmp}/declared" "${tmp}/packed" >&2; then
    echo "❌ the packed module does not ship exactly the files its package manifest declares (Go publishes only committed files)" >&2
    exit 1
  fi

  echo "🔎 Importing ${#packages[@]} public packages, building, vetting and testing..."
  go build -o "${tmp}/consumer.bin" .
  go vet ./...
  go test ./...
)

echo "✅ consumer test: ${module} packs, installs by local replace, imports, builds, vets and tests"
