#!/usr/bin/env bash
set -euo pipefail

bin="${1:?Usage: smoke.sh <path-to-binary>}"
chmod +x "${bin}"
xattr -d com.apple.quarantine "${bin}" 2>/dev/null || true

name="$(jq -r '.bin | to_entries[0].key' package.json)"
[ -z "${name}" ] && echo "❌ no .bin entry in package.json" >&2 && exit 1
[ "${name}" = "null" ] && echo "❌ no .bin entry in package.json" >&2 && exit 1

"${bin}" --version
help="$("${bin}" --help)"
printf '%s\n' "${help}"

! grep -q 'Usage:' <<<"${help}" && echo "❌ --help is missing its usage banner" >&2 && exit 1
! grep -q "${name}" <<<"${help}" && echo "❌ --help does not name '${name}'" >&2 && exit 1

msg_file="$(mktemp)"
trap 'rm -f "${msg_file}"' EXIT
printf '%s\n' 'feat: add a release capability' >"${msg_file}"
"${bin}" lint-commit "${msg_file}" -c release.yaml
echo "✅ lint-commit ok"

echo "✅ smoke ok: ${bin}"
