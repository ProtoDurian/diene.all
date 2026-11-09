#!/usr/bin/env bash
set -euo pipefail

mode="${1:-}"
config="release.yaml"
tmp="$(mktemp -d)"
trap 'rm -rf "${tmp}"' EXIT

accepts() {
  printf '%s: check\n' "$1" >"${tmp}/msg"
  releaser lint-commit -c "${2:-${config}}" "${tmp}/msg" >/dev/null 2>&1
}

declared="$(yq -r '.types[].type' "${config}" | LC_ALL=C sort)"

case "${mode}" in
parse)
  yq e '.' "${config}" >/dev/null
  accepts chore || { echo "❌ ${config} is not a valid releaser configuration" >&2 && exit 1; }
  ;;
vocabulary)
  grep -qx dep <<<"${declared}" || { echo "❌ ${config} lacks the dep type" >&2 && exit 1; }
  grep -qx upstream <<<"${declared}" && echo "❌ ${config} declares the retired upstream type" >&2 && exit 1
  accepts 'dep(upstream)' || accepts dep || { echo "❌ releaser lint-commit rejects dep" >&2 && exit 1; }
  ;;
types)
  hook_config="$(sed -n 's#.*releaser lint-commit -c \([^ "]*\)".*#\1#p' nix/pre-commit.nix)"
  [ -z "${hook_config}" ] && echo "❌ nix/pre-commit.nix has no releaser lint-commit hook" >&2 && exit 1
  accepted=""
  for t in ${declared} amend upstream wip revert release hotfix deps bogus; do
    if accepts "${t}" "${hook_config}"; then accepted+="${t}"$'\n'; fi
  done
  accepted="$(printf '%s' "${accepted}" | LC_ALL=C sort -u)"
  [ "${accepted}" != "${declared}" ] && echo "❌ the commit-msg hook (releaser lint-commit -c ${hook_config}) accepts [${accepted//$'\n'/ }] but ${config} declares [${declared//$'\n'/ }]" >&2 && exit 1
  ;;
*)
  echo "❌ unknown release lint mode '${mode}'" >&2
  exit 1
  ;;
esac

echo "✅ release ${mode} check passed"
