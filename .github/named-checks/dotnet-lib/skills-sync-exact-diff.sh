#!/usr/bin/env bash
set -euo pipefail

# The vendored-skill tree is exactly what skills-sync writes: a frozen sync changes
# nothing and the index agrees with it.

cd "$(git rev-parse --show-toplevel)"

if ! skills-sync sync --frozen; then
  echo "❌ skills-sync --frozen found drift between the vendor tree and skills-sync.yaml" >&2
  exit 1
fi
if [[ -n "$(git status --porcelain -- .claude/skills)" ]]; then
  echo "❌ skills-sync left changes under .claude/skills" >&2
  exit 1
fi

echo "✅ skills-sync-exact-diff: frozen sync is clean"
