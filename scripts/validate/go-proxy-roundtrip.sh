#!/usr/bin/env bash
set -euo pipefail

tag="${1:-}"
module="$(yq -r '.module' .config/go-lib.yaml)"
proxy="${GOPROXY_URL:-$(yq -r '.proxy' .config/go-lib.yaml)}"
tmp="$(mktemp -d)"
trap 'chmod -R u+w "${tmp}" 2>/dev/null || true; rm -rf "${tmp}"' EXIT

./scripts/validate/go-publish-guard.sh "${tag}"
cd "${tmp}"
export GOENV=off GOWORK=off GOPRIVATE='' GONOPROXY='' GONOSUMDB='' GOPATH="${tmp}/gopath" GOMODCACHE="${tmp}/modcache" GOPROXY="${proxy}" GOSUMDB=sum.golang.org GOFLAGS=-mod=mod
go mod init example.invalid/go-lib-consumer >/dev/null 2>&1
go get "${module}@${tag}"
printf 'package main\n\nimport (\n\t"fmt"\n\n\t"%s/lib/note"\n)\n\nfunc main() { fmt.Println(note.NewKeyComposer("notes").Slug("Proxy Round Trip")) }\n' "${module}" >main.go
go build -o consumer .
[ "$(./consumer)" != "proxy-round-trip" ] && echo "❌ proxy consumer returned an unexpected result" >&2 && exit 1

echo "✅ Go proxy resolved ${module}@${tag} into a clean consumer"
