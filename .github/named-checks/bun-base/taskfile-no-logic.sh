#!/usr/bin/env bash
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

parent_sha="${NAMED_CHECKS_PARENT_SHA:-$(cat .github/named-checks/bun-base/parent.sha)}"
git rev-parse --verify --quiet "${parent_sha}^{commit}" >/dev/null || git fetch --quiet --no-tags origin "${parent_sha}" || true
git rev-parse --verify --quiet "${parent_sha}^{commit}" >/dev/null || { echo "❌ shared .3 commit ${parent_sha} not found; fetch it first" >&2 && exit 1; }

# Shell control flow only; simple command chains, `|| true` and {{...}} template expressions are allowed.
control='(^|[;&|(){!])[[:space:]]*((if|elif|else|fi|case|esac|for|while|until|select|function)([[:space:];&|()]|$)|[[:alnum:]_.-]+[[:space:]]*\([[:space:]]*\))'
# Quoted text and {{...}} templates are data, not shell syntax.
data='s/\{\{[^}]*\}\}//g; s/'"'"'[^'"'"']*'"'"'//g; s/"([^"\\]|\\.)*"//g'
# Every task form: a string, a list, or a map with cmd/cmds; each cmd a string or {cmd: ...}.
cmds='[.tasks[] | (select(tag == "!!str"), (select(tag == "!!seq") | .[]), (select(tag == "!!map") | (.cmd, (.cmds // [])[])))] | .[] | select(tag == "!!str" or (tag == "!!map" and has("cmd"))) | with(select(tag == "!!map"); . = .cmd)'
failed=0

# A line the parent already carries is reported, not failed: it is fixed in the parent.
judge() {
  local inherited="$1" file="$2" line="$3" what="$4"
  if grep -Fxq -- "${line}" <<<"${inherited}"; then
    echo "⚠️ inherited ${what} in ${file} (fix in the parent): ${line}"
  else
    echo "❌ ${what} in ${file}: ${line}" >&2
    failed=1
  fi
}

shopt -s nullglob
for file in Taskfile.yaml tasks/*.yaml; do
  parent="$(git show "${parent_sha}:${file}" 2>/dev/null || true)"
  parent_cmds="$(yq "${cmds}" <<<"${parent}" 2>/dev/null || true)"
  while IFS= read -r line; do
    if [[ "$(sed -E "${data}" <<<"${line}")" =~ ${control} ]]; then
      judge "${parent_cmds}" "${file}" "${line}" "shell control flow in a task cmd"
    fi
  done < <(yq "${cmds}" "${file}")
  while IFS= read -r line; do
    judge "${parent}" "${file}" "${line}" "scripts/ci call"
  done < <(rg -N 'scripts/ci/' "${file}" || true)
done

[[ ${failed} -eq 0 ]] || exit 1
echo "✅ taskfile-no-logic: no task cmd control flow or scripts/ci call added over shared .3 ${parent_sha}"
