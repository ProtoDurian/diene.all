#!/usr/bin/env bash
set -euo pipefail

# The vendored-skill tree is exactly what skills-sync writes: a frozen sync changes
# nothing, and with no runtime declared nothing is vendored at all.

cd "$(git rev-parse --show-toplevel)"

if ! skills-sync sync --frozen; then
  echo "❌ skills-sync --frozen found drift between the vendor tree and skills-sync.yaml" >&2
  exit 1
fi
if [[ -n "$(git status --porcelain -- .claude/skills)" ]]; then
  echo "❌ skills-sync left changes under .claude/skills" >&2
  exit 1
fi
if [[ "$(yq '.runtimes // [] | length' skills-sync.yaml)" == 0 ]]; then
  vendored="$(git ls-files -- .claude/skills/vendor ':!.claude/skills/vendor/.gitkeep' ':!.claude/skills/vendor/manifest.json')"
  if [[ -n ${vendored} || "$(jq 'length' .claude/skills/vendor/manifest.json)" != 0 ]]; then
    echo "❌ skills-sync declares no runtime but .claude/skills/vendor tracks vendored skills" >&2
    exit 1
  fi
fi

echo "✅ skills-sync-exact-diff: frozen sync is clean"
