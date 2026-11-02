#!/usr/bin/env bash
set -euo pipefail

# Binaries the owner retired stay out of the nix inventory (goals/workspace.md,
# binary smoke: `pls` is gone, go-task is the one task runner; the releaser
# replaced `sg`). A text check on the declaration, not `command -v`, because the
# dev shell inherits the caller's PATH. An absence search is a named check, not
# a probe (rules/PROBES.md §2 item 10).

declaration_files=(nix/packages.nix nix/env.nix)
retired=(pls sg)
failed=0

for file in "${declaration_files[@]}"; do
  if [[ ! -f ${file} ]]; then
    echo "❌ ${file} is missing; nothing to search (vacuous)" >&2
    exit 1
  fi
done

for binary in "${retired[@]}"; do
  if hits="$(rg --line-number --word-regexp --fixed-strings -- "${binary}" "${declaration_files[@]}")"; then
    echo "❌ ${binary} is declared in the nix inventory again:" >&2
    echo "${hits}" >&2
    failed=1
  fi
done

if [[ ${failed} != 0 ]]; then
  exit 1
fi

echo "retired binaries: ${retired[*]} absent from ${declaration_files[*]}"
