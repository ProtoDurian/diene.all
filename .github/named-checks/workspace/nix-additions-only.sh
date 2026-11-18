#!/usr/bin/env bash
set -euo pipefail

main_ref="${NAMED_CHECKS_MAIN_REF:-origin/main}"

if ! git rev-parse --verify --quiet "${main_ref}^{commit}" >/dev/null; then
  echo "❌ ${main_ref} not found; fetch it first (git fetch origin main)" >&2
  exit 1
fi

tree="$(git write-tree)"
failed=0

if [[ -z "$(git ls-tree --name-only "${main_ref}" -- nix/ | grep '\.nix$' || true)" ]]; then
  echo "❌ ${main_ref} tracks no nix/*.nix; nothing to compare (vacuous)" >&2
  exit 1
fi

if ! git diff --quiet "${main_ref}" "${tree}" -- flake.nix; then
  echo "❌ flake.nix differs from ${main_ref}; nix changes belong in main" >&2
  failed=1
fi

while IFS=$'\t' read -r _ deleted path; do
  if [[ ${deleted} != 0 ]]; then
    echo "❌ ${path}: ${deleted} line(s) of ${main_ref} deleted; extend it, do not rewrite it" >&2
    failed=1
  fi
done < <(git -c core.quotePath=false diff --no-renames --numstat "${main_ref}" "${tree}" -- 'nix/*.nix')

if [[ ${failed} != 0 ]]; then
  exit 1
fi

echo "nix additions-only: flake.nix equals ${main_ref}; no nix/*.nix line of it deleted"
