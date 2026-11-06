#!/usr/bin/env bash
set -euo pipefail

[ -z "${FURY_TOKEN:-}" ] && echo "❌ 'FURY_TOKEN' env var not set" >&2 && exit 1
[ -z "${FURY_ENDPOINT:-}" ] && echo "❌ 'FURY_ENDPOINT' env var not set" >&2 && exit 1

endpoint="${FURY_ENDPOINT}"

# Keep the token out of argv: curl reads it from a 0600 config removed on exit.
credential_config="$(mktemp)"
chmod 600 "${credential_config}"
trap 'rm -f -- "${credential_config}"' EXIT
{
  printf 'user = "'
  printf '%s' "${FURY_TOKEN}" | sed 's/\\/\\\\/g; s/"/\\"/g'
  printf ':"\n'
} >"${credential_config}"

shopt -s nullglob
packages=(dist/*.deb)
[ "${#packages[@]}" -eq 0 ] && echo "❌ no deb packages found in dist/" >&2 && exit 1

for pkg in "${packages[@]}"; do
  echo "📤 pushing ${pkg} -> ${endpoint}"
  curl --config "${credential_config}" -fsS --connect-timeout 30 --max-time 600 -F package=@"${pkg}" "https://${endpoint}/"
done

echo "✅ pushed ${#packages[@]} package(s) to Gemfury"
