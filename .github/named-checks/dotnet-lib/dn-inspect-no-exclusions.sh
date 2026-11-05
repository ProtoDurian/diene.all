#!/usr/bin/env bash
set -euo pipefail

# index tree == HEAD in CI; keeps local staged mutations visible
tree="$(git write-tree)"
failed=0
files="$(git -c core.quotePath=false ls-tree -r --name-only "${tree}")"

for script in scripts/local/dotnet-dead-code.sh scripts/ci/dead-code.sh; do
  if ! grep -qx "${script}" <<<"${files}"; then
    echo "❌ ${script} is missing" >&2
    failed=1
  elif git show "${tree}:${script}" | grep -nE -- '--(include|exclude)\b'; then
    echo "❌ ${script} narrows dn-inspect" >&2
    failed=1
  fi
done

settings="$(grep -E '(^|/)(\.editorconfig|[^/]+\.DotSettings|\.globalconfig)$' <<<"${files}" | grep -v '^\.claude/skills/vendor/' || true)"
if [[ -n ${settings} ]]; then
  while IFS= read -r path; do
    if git show "${tree}:${path}" | grep -niE 'resharper_[a-z_]+_highlighting|InspectionSeverities|severity *= *(none|silent)'; then
      echo "❌ ${path} switches an inspection off" >&2
      failed=1
    fi
  done <<<"${settings}"
fi

while IFS= read -r path; do
  if git show "${tree}:${path}" | grep -nE 'ReSharper disable|#pragma warning disable|SuppressMessage'; then
    echo "❌ ${path} suppresses an inspection" >&2
    failed=1
  fi
done < <(grep -E '\.cs$' <<<"${files}" || true)

while IFS= read -r path; do
  if git show "${tree}:${path}" | grep -nE '<NoWarn>'; then
    echo "❌ ${path} switches a diagnostic off" >&2
    failed=1
  fi
done < <(grep -E '\.(csproj|props|targets)$' <<<"${files}" || true)

if [[ ${failed} -ne 0 ]]; then
  exit 1
fi

echo "✅ dn-inspect-no-exclusions: no dn-inspect narrowing, settings or source suppressions"
