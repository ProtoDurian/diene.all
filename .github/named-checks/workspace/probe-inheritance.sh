#!/usr/bin/env bash
set -euo pipefail

# The probes the nix layer (main) owns are inherited, never rewritten
# (rules/PROBES.md §5). On a branch both ledger rows of a feature load the same
# probes/<name>.ts, so an edited inherited file is a hidden override. Per file
# tracked at main:
#   - no line of main's file is deleted (byte-identical or append-only);
#   - appended lines (additive) need a diene/workspace row of that name;
#   - a byte-identical file (parent suffices) has no diene/workspace row.
# Every probes/features.json row of main stays in the ledger unchanged.

main_ref="${NAMED_CHECKS_MAIN_REF:-origin/main}"
child=diene/workspace

if ! git rev-parse --verify --quiet "${main_ref}^{commit}" >/dev/null; then
  echo "❌ ${main_ref} not found; fetch it first (git fetch origin main)" >&2
  exit 1
fi

# index tree == HEAD in CI; keeps local staged mutations visible
tree="$(git write-tree)"
ledger="$(git show "${tree}:probes/features.json")"
failed=0

mapfile -t inherited < <(git ls-tree --name-only "${main_ref}" -- probes/ | grep '\.ts$' || true)
if [[ ${#inherited[@]} -eq 0 ]]; then
  echo "❌ ${main_ref} tracks no probes/*.ts; nothing to compare (vacuous)" >&2
  exit 1
fi

for path in "${inherited[@]}"; do
  name="$(basename "${path}" .ts)"
  if ! git cat-file -e "${tree}:${path}" 2>/dev/null; then
    echo "❌ ${path}: main's probe file is gone" >&2
    failed=1
    continue
  fi
  # an identical file prints no numstat line
  numstat="$(git diff --no-renames --numstat "${main_ref}" "${tree}" -- "${path}")"
  read -r added deleted _ <<<"${numstat:-0 0 ${path}}"
  has_row="$(jq --arg t "${child}" --arg n "${name}" '[.[] | select(.template == $t and .name == $n)] | length' <<<"${ledger}")"
  if [[ ${deleted} != 0 ]]; then
    echo "❌ ${path}: ${deleted} line(s) of ${main_ref} changed or deleted; inherit it unchanged or append" >&2
    failed=1
  elif [[ ${added} != 0 && ${has_row} == 0 ]]; then
    echo "❌ ${path}: appends probes but probes/features.json has no ${child} row '${name}'" >&2
    failed=1
  elif [[ ${added} == 0 && ${has_row} != 0 ]]; then
    echo "❌ ${path}: byte-identical to ${main_ref} but probes/features.json still has a ${child} row '${name}' (parent suffices)" >&2
    failed=1
  fi
done

missing="$(jq -n --argjson main "$(git show "${main_ref}:probes/features.json")" --argjson tree "${ledger}" \
  '[$main[] | select(. as $row | $tree | index([$row]) | not)]')"
if [[ ${missing} != "[]" ]]; then
  echo "❌ probes/features.json lost or changed rows of ${main_ref}: ${missing}" >&2
  failed=1
fi

if [[ ${failed} != 0 ]]; then
  exit 1
fi

echo "probe inheritance: ${#inherited[@]} probe files of ${main_ref} inherited unchanged or append-only; ledger rows match"
