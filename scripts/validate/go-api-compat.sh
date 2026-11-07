#!/usr/bin/env bash
set -euo pipefail

module="$(yq -r '.module' .config/go-lib.yaml)"
baseline="$(yq -r '.apiBaseline' .config/go-lib.yaml)"
candidate="$(yq -r '.apiCandidate' .config/go-lib.yaml)"
# The module proxy protocol escapes each upper-case letter as '!' + its lower case.
escaped=""
for ((i = 0; i < ${#module}; i++)); do
  char="${module:i:1}"
  [[ ${char} == [A-Z] ]] && char="!${char,,}"
  escaped+="${char}"
done
tmp="$(mktemp -d)"
trap 'chmod -R u+w "${tmp}" 2>/dev/null || true; rm -rf "${tmp}"' EXIT

source="${tmp}/${module}@${baseline}"
versions="${tmp}/proxy/${escaped}/@v"
release="${tmp}/release"
mkdir -p "${source}" "${versions}" "${release}"
cp -R tests/fixtures/api-baseline/. "${source}/"
cp go.mod go.sum "${source}/"
printf '%s\n' "${baseline}" >"${versions}/list"
printf '{"Version":"%s","Time":"2026-01-01T00:00:00Z"}\n' "${baseline}" >"${versions}/${baseline}.info"
cp "${source}/go.mod" "${versions}/${baseline}.mod"
(cd "${tmp}" && zip -qr "${versions}/${baseline}.zip" "${module}@${baseline}")
tar --exclude=./.git --exclude=./.direnv --exclude=./coverage --exclude=./dist --exclude=./reports --exclude=./tests --exclude=./probes -cf - . | tar -C "${release}" -xf -

(
  cd "${release}"
  export GOPATH="${tmp}/gopath" GOMODCACHE="${tmp}/modcache" GOCACHE="${tmp}/gocache"
  export GOPROXY="file://${tmp}/proxy,${GOPROXY:-https://proxy.golang.org}" GONOSUMDB="${module}" GOFLAGS=-mod=mod
  gorelease -base="${baseline}" -version="${candidate}"
)

echo "✅ Go public API is compatible with ${baseline}"
