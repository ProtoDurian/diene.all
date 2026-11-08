#!/usr/bin/env bash
set -euo pipefail

[ -z "${VERSION:-}" ] && echo "❌ 'VERSION' env var not set" >&2 && exit 1

echo "Released ${VERSION}"
