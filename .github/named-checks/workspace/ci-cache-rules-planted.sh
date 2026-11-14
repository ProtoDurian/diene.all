#!/usr/bin/env bash
set -euo pipefail

# Self-test of ci-cache-rules.sh: the copied workflows are green, and each planted change turns the check red.

cd "$(git rev-parse --show-toplevel)"

rules=".github/named-checks/workspace/ci-cache-rules.sh"
tmp="$(mktemp -d)"
trap 'rm -rf "${tmp}"' EXIT

fresh() {
  rm -rf "${tmp}/w"
  cp -r .github/workflows "${tmp}/w"
}

nix_file="${tmp}/w/⚡reusable-named-checks.yaml"
note_file="${tmp}/w/⚡reusable-release-note.yaml"
idt="id-""token"
top_id=$'permissions:\n  '"${idt}"$': write\n\njobs:\n'

fresh
if ! "${rules}" "${tmp}/w" >/dev/null 2>&1; then
  echo "❌ unchanged workflows are red" >&2
  exit 1
fi

fail=0
expect_red() {
  local name="$1" reason="$2" out
  if out="$("${rules}" "${tmp}/w" 2>&1)"; then
    echo "❌ planted '${name}' stayed green" >&2
    fail=1
  elif ! grep -qF -- "${reason}" <<<"${out}"; then
    echo "❌ planted '${name}' is red without '${reason}'" >&2
    fail=1
  else
    echo "✅ planted '${name}' is red"
  fi
}

fresh
sed -i 's|runs-on: ubuntu-26.04|runs-on: [ubuntu-26.04, nscloud-cache-tag-nix-store-cache-ubuntu-26.04-amd64]|' "${note_file}"
expect_red "cache tag without setup-nix" "no AtomiCloud/actions.setup-nix step"

fresh
sed -i "s|^    timeout-minutes: 20\$|&\\n    permissions:\\n      ${idt}: write|" "${nix_file}"
expect_red "job permission without flakehub-login" "flakehub-login"

fresh
sed -i "s|^jobs:\$|${top_id//$'\n'/\\n}|" "${nix_file}"
expect_red "workflow permission without flakehub-login" "flakehub-login"

fresh
sed -i "s|^jobs:\$|${top_id//$'\n'/\\n}|" "${nix_file}"
sed -i "s|^\( *\)devshell-cache: 'true'\$|&\n\1flakehub-login: 'false'\n      - uses: AtomiCloud/actions.setup-nix@v3|" "${nix_file}"
expect_red "second setup-nix without flakehub-login" "flakehub-login"

fresh
sed -i '/^    env:$/{N;/DURIAN_SHELL_KEEP/d}' "${nix_file}"
expect_red "devshell-cache without DURIAN_SHELL_KEEP" "DURIAN_SHELL_KEEP"

[ "${fail}" -eq 0 ] || exit 1
echo "✅ ci-cache-rules is green unchanged and red on every planted case"
