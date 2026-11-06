#!/usr/bin/env bash
set -euo pipefail

entry="$(jq -r '.bin | to_entries[0].value' package.json)"
name="$(jq -r '.bin | to_entries[0].key' package.json)"
[ -z "${entry}" ] || [ "${entry}" = "null" ] && echo "❌ no .bin entry in package.json" >&2 && exit 1

outdir="${COMPILE_OUTDIR:-dist/bin}"
mkdir -p "${outdir}"

echo "🔨 compiling ${entry} -> ${outdir}/${name} (host target)"
bun build "./${entry}" --compile --minify --outfile "${outdir}/${name}"
echo "✅ compiled ${outdir}/${name}"
