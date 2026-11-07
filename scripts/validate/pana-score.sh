#!/usr/bin/env bash
set -euo pipefail

root_dir="$(git rev-parse --show-toplevel)"
export FLUTTER_ROOT="${FLUTTER_ROOT:-$(dirname "$(dirname "$(command -v flutter)")")}"
cd "${root_dir}/packages/diene_e2e"

report="$(mktemp)"
trap 'rm -f "${report}"' EXIT

pana_args=(--no-dartdoc --json --flutter-sdk "${FLUTTER_ROOT}")
[[ -n ${PUB_HOSTED_URL:-} ]] && pana_args+=(--hosted-url "${PUB_HOSTED_URL}")
dart pub global activate pana 0.23.14 >/dev/null
dart pub global run pana "${pana_args[@]}" . >"${report}"

# Mirror main is the pre-transfer seed until the owner publishes it; drop this allowance then.
verdict="$(jq -r '
  (.scores.maxPoints - .scores.grantedPoints) as $lost
  | [.report.sections[] | select(.grantedPoints < .maxPoints)] as $failed
  | if $lost == 0 then "perfect"
    elif $lost == 10 and ($failed | length) == 1 and $failed[0].id == "convention"
      and ($failed[0].summary | [scan("<summary>")] | length) == 1
      and ($failed[0].summary | test("Failed to verify repository URL[.]"))
      and ($failed[0].summary | test("but got `https://github[.]com/AtomiCloud/diene[.]dart_e2e`"))
    then "mirror-main-seed"
    else "lost \($lost): " + ([$failed[] | "\(.id) \(.grantedPoints)/\(.maxPoints)"] | join(", "))
    end' "${report}")"

case "${verdict}" in
perfect) echo "✅ pana score is perfect" ;;
mirror-main-seed) echo "✅ pana score is perfect apart from the repository check against the unpublished mirror main" ;;
*)
  jq -r '.report.sections[] | select(.grantedPoints < .maxPoints) | .summary' "${report}" >&2
  echo "❌ pana ${verdict}" >&2
  exit 1
  ;;
esac
