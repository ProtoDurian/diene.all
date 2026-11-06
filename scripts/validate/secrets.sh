#!/usr/bin/env bash
set -euo pipefail

root_dir="$(git rev-parse --show-toplevel)"
cd "${root_dir}"

sealed_pattern='^ENC\[AES256_GCM,data:[A-Za-z0-9+/=]*,iv:[A-Za-z0-9+/=]+,tag:[A-Za-z0-9+/=]+,type:(str|int|float|bool|bytes)\]$'
mapfile -t files < <(git ls-files --cached --others --exclude-standard -- secrets | sort -u)
[ "${#files[@]}" -eq 0 ] && echo "❌ secrets/ holds no sealed file" >&2 && exit 1

echo "🔐 Checking that every value under secrets/ is sealed..."
expected_keys=""
for file in "${files[@]}"; do
  [[ ! ${file} =~ ^secrets/[^/]+\.yaml$ ]] && echo "❌ ${file}: only sealed secrets/<env>.yaml files may live under secrets/" >&2 && exit 1
  [ "$(yq '.sops.mac // "" | length > 0' "${file}")" != "true" ] && echo "❌ ${file}: not a SOPS file (no sops.mac)" >&2 && exit 1
  unsealed="$(yq -o=json 'del(.sops)' "${file}" | jq -r --arg p "${sealed_pattern}" \
    'to_entries[] | select((.value | type) != "string" or (.value | test($p) | not)) | .key')"
  [ -n "${unsealed}" ] && echo "❌ ${file}: $(echo "${unsealed}" | paste -sd, -) is not sealed (must be a flat key: ENC[...] value)" >&2 && exit 1
  keys="$(yq 'del(.sops) | keys | .[]' "${file}" | sort)"
  expected_keys="${expected_keys:-${keys}}"
  [ "${keys}" != "${expected_keys}" ] && echo "❌ ${file}: key set differs from ${files[0]}" >&2 && exit 1
done

echo "🔐 Comparing sealed keys with OpenTofu sensitive variables..."
tofu_keys="$(awk '
  /^variable "/ { name = $2; gsub(/"/, "", name) }
  /^}/ { name = "" }
  name != "" && /^[[:space:]]*sensitive[[:space:]]*=[[:space:]]*true/ { print toupper(name) }
' infra/tofu/*.tf | sort)"
only_sealed="$(comm -23 <(echo "${expected_keys}") <(echo "${tofu_keys}") | paste -sd, -)"
only_tofu="$(comm -13 <(echo "${expected_keys}") <(echo "${tofu_keys}") | paste -sd, -)"
[ -n "${only_sealed}" ] && echo "❌ sealed but not a sensitive variable in infra/tofu: ${only_sealed}" >&2 && exit 1
[ -n "${only_tofu}" ] && echo "❌ sensitive variable in infra/tofu but not sealed in secrets/: ${only_tofu}" >&2 && exit 1

echo "🔐 Comparing Worker secrets in infra/tofu with wrangler.jsonc..."
worker_map="$(awk '
  /^output "worker_secrets"/ { inside = 1; next }
  inside && /^}/ { inside = 0 }
  inside && /^[[:space:]]+[A-Z0-9_]+[[:space:]]*=[[:space:]]*var\.[a-z0-9_]+[[:space:]]*$/ { print $1, $3 }
' infra/tofu/*.tf | sort)"
[ -z "${worker_map}" ] && echo "❌ infra/tofu has no worker_secrets output" >&2 && exit 1
mismatched="$(echo "${worker_map}" | awk '"var." tolower($1) != $2 { print $1 }' | paste -sd, -)"
[ -n "${mismatched}" ] && echo "❌ worker_secrets must map each KEY to var.key: ${mismatched}" >&2 && exit 1
worker_keys="$(echo "${worker_map}" | awk '{ print $1 }')"
not_sealed="$(comm -13 <(echo "${expected_keys}") <(echo "${worker_keys}") | paste -sd, -)"
[ -n "${not_sealed}" ] && echo "❌ Worker secret not sealed in secrets/: ${not_sealed}" >&2 && exit 1
wrangler_lists="$(bun -e 'process.stdout.write(JSON.stringify(Bun.JSONC.parse(await Bun.file("wrangler.jsonc").text())))' |
  jq -r '[{ where: "top level", c: . }] + [(.env // {}) | to_entries[] | { where: "env.\(.key)", c: .value }]
    | .[] | "\(.where)\t\((.c.secrets.required // []) | sort | join(","))"')"
expected_required="$(echo "${worker_keys}" | paste -sd, -)"
wrong_required="$(echo "${wrangler_lists}" | awk -F '\t' -v want="${expected_required}" '$2 != want { print $1 " has [" $2 "]" }')"
[ -n "${wrong_required}" ] && echo "❌ wrangler.jsonc secrets.required must be [${expected_required}]: ${wrong_required}" >&2 && exit 1

echo "🔐 Looking for plain secrets elsewhere in the tree..."
age_key_pattern='AGE-SECRET-KEY-1[0-9A-Z]{58}'
leaked_key="$(git grep -lIE --untracked "${age_key_pattern}" || true)"
[ -n "${leaked_key}" ] && echo "❌ age private key found in: ${leaked_key}" >&2 && exit 1
plain_files="$(git ls-files --cached --others --exclude-standard |
  grep -E '(^|/)(\.dev\.vars|\.env(\..+)?|[^/]+\.agekey|[^/]+\.tfstate(\..+)?)$' | grep -vE '(^|/)\.env\.example$' || true)"
[ -n "${plain_files}" ] && echo "❌ plain secret files must never be committed: ${plain_files}" >&2 && exit 1
tofu_names="$(echo "${tofu_keys}" | tr '[:upper:]' '[:lower:]' | paste -sd '|' -)"
tfvars_hits="$(git ls-files --cached --others --exclude-standard -- '*.tfvars' '*.tfvars.json' |
  xargs -r grep -lE "(^|[[:space:]\"])(${tofu_names})\"?[[:space:]]*[=:]" || true)"
[ -n "${tfvars_hits}" ] && echo "❌ sensitive variables must come from secrets/, not tfvars: ${tfvars_hits}" >&2 && exit 1

for file in "${files[@]}"; do
  plain="$(sops decrypt --output-type json "${file}" 2>/dev/null || true)"
  [ -z "${plain}" ] && echo "📝 ${file}: no local age key opens it; skipped the decrypted-value scan" && continue
  hits="$(echo "${plain}" | jq -r '.[] | tostring | select(length >= 8)' |
    git grep -lIF --untracked -f /dev/stdin -- . ':!secrets/' || true)"
  [ -n "${hits}" ] && echo "❌ a decrypted value from ${file} appears in plain text in: ${hits}" >&2 && exit 1
done

echo "✅ Sealed secrets hold: $(echo "${expected_keys}" | wc -l) keys sealed, matched in infra/tofu and wrangler.jsonc"
