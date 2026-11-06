#!/usr/bin/env bash
set -euo pipefail

[ "$#" -gt 0 ] && echo "❌ secrets-init.sh takes no arguments" >&2 && exit 1

root_dir="$(git rev-parse --show-toplevel)"
cd "${root_dir}"

key_file="${SOPS_AGE_KEY_FILE:-${XDG_CONFIG_HOME:-${HOME}/.config}/sops/age/keys.txt}"

echo "🔐 Using age key ${key_file}..."
mkdir -p "$(dirname "${key_file}")"
[ -f "${key_file}" ] || age-keygen -o "${key_file}" 2>/dev/null
chmod 600 "${key_file}"
recipient="$(age-keygen -y "${key_file}")"

echo "📝 Sealing secrets/ to ${recipient}..."
RECIPIENT="${recipient}" yq -i '.creation_rules[0].age = strenv(RECIPIENT)' .sops.yaml

# Plain values only ever go through a pipe, never to disk.
for file in secrets/*.yaml; do
  if SOPS_AGE_KEY_FILE="${key_file}" sops decrypt "${file}" >/dev/null 2>&1; then
    SOPS_AGE_KEY_FILE="${key_file}" sops updatekeys --yes "${file}"
    echo "✅ ${file}: re-encrypted, values kept"
    continue
  fi
  yq 'del(.sops) | keys | .[]' "${file}" |
    while read -r key; do echo "${key}: $(openssl rand -hex 32)"; done |
    sops encrypt --filename-override "${file}" --input-type yaml --output-type yaml /dev/stdin >"${file}.sealed"
  mv "${file}.sealed" "${file}"
  echo "✅ ${file}: re-sealed with random placeholders; set real values with: sops edit ${file}"
done

echo "📝 Keep ${key_file} private. CI needs only its contents, as the SOPS_AGE_KEY secret."
