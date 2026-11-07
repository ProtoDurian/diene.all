#!/usr/bin/env bash
set -euo pipefail

echo "🔍 Running production deadcode without test reachability"
report="$(./scripts/local/with-deadcode-consumer.sh deadcode -json ./...)"
[ -z "${report}" ] && echo "❌ production deadcode produced no report" >&2 && exit 1
count="$(jq '(. // []) | length' <<<"${report}")"
[ "${count}" -ne 0 ] && jq . <<<"${report}" >&2 && exit 1

echo "✅ Go deadcode production pass complete"
