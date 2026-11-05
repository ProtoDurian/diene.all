#!/usr/bin/env bash
set -euo pipefail

# Q-G22: from v1.15 on, every first-parent step from the base to HEAD may move cert-manager by at most one minor.
cd "$(git rev-parse --show-toplevel)"

pin_at() {
  git show "$1:chart/Chart.yaml" 2>/dev/null | yq -r '.dependencies[] | select(.name == "cert-manager") | .version' 2>/dev/null || true
}

base="${SEQ_BASE:-}"
if [ -z "${base}" ] && [ -n "${GITHUB_EVENT_PATH:-}" ] && [ -s "${GITHUB_EVENT_PATH}" ]; then
  base="$(jq -r '.before // .pull_request.base.sha // empty' "${GITHUB_EVENT_PATH}")"
  [[ ${base} =~ ^0+$ ]] && base=""
fi
[ -n "${base}" ] || base="HEAD^1"
git rev-parse --verify --quiet "${base}^{commit}" >/dev/null || { echo "❌ sequential-minor base ${base} is not in the local history" >&2 && exit 1; }

head_pin="$(pin_at HEAD)"
[[ ${head_pin} =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "❌ HEAD pins cert-manager '${head_pin}', not an exact vX.Y.Z" >&2 && exit 1; }

steps=0
while read -r commit; do
  parent="$(git rev-parse --verify --quiet "${commit}^1" || true)"
  [ -n "${parent}" ] || continue
  from="$(pin_at "${parent}")" to="$(pin_at "${commit}")"
  [ -n "${from}" ] && [ -n "${to}" ] || continue
  IFS=. read -r from_major from_minor _ <<<"${from#v}"
  IFS=. read -r to_major to_minor _ <<<"${to#v}"
  [ "${from_major}" -eq 1 ] && [ "${from_minor}" -lt 15 ] && continue
  steps=$((steps + 1))
  short="$(git rev-parse --short "${commit}")"
  [ "${to_major}" = "${from_major}" ] || { echo "❌ ${short}: cert-manager major change ${from} -> ${to} is not a sequential-minor bump" >&2 && exit 1; }
  delta=$((to_minor - from_minor))
  [ "${delta}" -ge 0 ] || { echo "❌ ${short}: cert-manager downgrade ${from} -> ${to}" >&2 && exit 1; }
  [ "${delta}" -le 1 ] || { echo "❌ ${short}: version-skip ${from} -> ${to} skips a cert-manager minor (sequential-minor only)" >&2 && exit 1; }
done < <(git rev-list --first-parent --reverse "${base}..HEAD")

echo "✅ sequential-minor: ${steps} step(s) from $(git rev-parse --short "${base}") to HEAD, none skips a minor; HEAD pins ${head_pin}"
