#!/usr/bin/env bash
set -euo pipefail

module="$(yq -r '.module' .config/go-lib.yaml)"
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
git config --global url."file://${source_repo}".insteadOf "https://${module}"

echo "📦 Packing ${module}@${revision} the way the module proxy does (go mod download from git)..."
packed="$(GOMODCACHE="${tmp}/pack-modcache" GOPROXY=direct GOPRIVATE="${module}" go mod download -json "${module}@${revision}" || true)"
version="$(jq -r '.Version' <<<"${packed}")"
dir="$(jq -r '.Dir' <<<"${packed}")"
[[ ! -d ${dir} ]] && echo "❌ go mod download did not pack ${module}: $(jq -r '.Error // "no Dir"' <<<"${packed}")" >&2 && exit 1

template=""
for field in GoFiles CgoFiles IgnoredGoFiles IgnoredOtherFiles TestGoFiles XTestGoFiles EmbedFiles TestEmbedFiles XTestEmbedFiles; do
  template+="{{range .${field}}}{{\$.ImportPath}}/{{.}}"$'\n'"{{end}}"
done
manifest() { go list -e -f "${template}" "$1" | LC_ALL=C sort; }
manifest ./... >"${tmp}/declared"
mapfile -t packages < <(go list -e -f '{{if and .GoFiles (ne .Name "main")}}{{.ImportPath}}{{end}}' ./...)
[[ ${#packages[@]} -eq 0 ]] && echo "❌ ${module} declares no importable package" >&2 && exit 1

echo "📥 Installing the packed ${module}@${version} into a fresh module by local replace..."
cat "${dir}/go.sum" >"${consumer}/go.sum"
{
  printf 'package main\n\nimport (\n\t"fmt"\n\n\t"%s/lib/note"\n' "${module}"
  for package in "${packages[@]}"; do printf '\t_ "%s"\n' "${package}"; done
  printf ')\n\nfunc main() { fmt.Println(note.NewKeyComposer("notes").Slug("Consumer Test")) }\n'
} >"${consumer}/main.go"
cat >"${consumer}/consumer_test.go" <<GO
package main_test

import (
	"context"
	"testing"

	"${module}/lib/note"
	"${module}/testhelper"
)

func TestPackedLibraryRoundTrip(t *testing.T) {
	service := note.NewService(testhelper.NewMemoryStore(), note.NewKeyComposer("notes"))
	created, err := service.Create(context.Background(), "Consumer Test", "packed")
	if err != nil {
		t.Fatal(err)
	}
	loaded, err := service.Load(context.Background(), created.Slug)
	if err != nil || loaded != created {
		t.Fatalf("loaded %+v, %v; want %+v", loaded, err, created)
	}
}
GO

(
  cd "${consumer}"
  export GOMODCACHE="${tmp}/modcache" GOPROXY="file://${user_modcache}/cache/download,${upstream_proxy}" GONOSUMDB="${module}"
  go mod init example.invalid/go-lib-consumer >/dev/null 2>&1
  go mod edit -require="${module}@v0.0.0-00010101000000-000000000000" -replace="${module}=${dir}"
  go mod tidy
  [[ "$(go list -m -f '{{.Replace.Dir}}' "${module}")" != "${dir}" ]] && echo "❌ ${module} did not resolve to the packed module" >&2 && exit 1

  echo "🔎 Comparing the packed module's files with the package manifest..."
  manifest "${module}/..." >"${tmp}/packed"
  if ! diff -u --label manifest --label packed "${tmp}/declared" "${tmp}/packed" >&2; then
    echo "❌ the packed module does not ship exactly the files its package manifest declares (Go publishes only committed files)" >&2
    exit 1
  fi

  echo "🔎 Importing ${#packages[@]} public packages, building, vetting and testing..."
  go build -o "${tmp}/consumer.bin" .
  [[ "$("${tmp}/consumer.bin")" != "consumer-test" ]] && echo "❌ the consumer returned an unexpected result" >&2 && exit 1
  go vet ./...
  go test ./...
)

echo "✅ consumer test: ${module} packs, installs by local replace, imports, builds, vets and tests"
