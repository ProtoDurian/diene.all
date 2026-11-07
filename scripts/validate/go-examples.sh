#!/usr/bin/env bash
set -euo pipefail

examples="$(go test -list '^Example' ./... | rg -c '^Example' || true)"
[ "${examples:-0}" -eq 0 ] && echo "❌ no Example functions found" >&2 && exit 1
go test -count=1 -run '^Example' ./...

echo "✅ ${examples} Go examples compile and pass"
