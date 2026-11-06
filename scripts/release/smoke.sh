#!/usr/bin/env bash
set -euo pipefail

bin="${1:?Usage: smoke.sh <path-to-binary>}"
chmod +x "${bin}"
xattr -d com.apple.quarantine "${bin}" 2>/dev/null || true

name="$(jq -r '.bin | to_entries[0].key' package.json)"
[ -z "${name}" ] && echo "❌ no .bin entry in package.json" >&2 && exit 1
[ "${name}" = "null" ] && echo "❌ no .bin entry in package.json" >&2 && exit 1
expected_version="$(jq -r '.version' package.json)"

version="$("${bin}" --version)"
printf '%s\n' "${version}"
[ "${version}" != "${expected_version}" ] && echo "❌ --version printed '${version}', expected '${expected_version}'" >&2 && exit 1

help="$("${bin}" --help)"
printf '%s\n' "${help}"
! grep -q 'Usage:' <<<"${help}" && echo "❌ --help is missing its usage banner" >&2 && exit 1
! grep -q "${name}" <<<"${help}" && echo "❌ --help does not name '${name}'" >&2 && exit 1
! grep -q 'fork create' <<<"${help}" && echo "❌ --help does not list 'fork create'" >&2 && exit 1
! grep -q 'migrate' <<<"${help}" && echo "❌ --help does not list 'migrate'" >&2 && exit 1

echo "✅ smoke ok: ${bin}"
