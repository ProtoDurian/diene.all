#!/usr/bin/env bash
set -euo pipefail

root_dir="$(git rev-parse --show-toplevel)"
export FLUTTER_ROOT="${FLUTTER_ROOT:-$(dirname "$(dirname "$(command -v flutter)")")}"
cd "${root_dir}/packages/diene_auth_engine"

report="$(mktemp)"
trap 'rm -f "${report}"' EXIT

pana_args=(--no-dartdoc --json --flutter-sdk "${FLUTTER_ROOT}")
[[ -n ${PUB_HOSTED_URL:-} ]] && pana_args+=(--hosted-url "${PUB_HOSTED_URL}")
dart pub global activate pana 0.23.14 >/dev/null
dart pub global run pana "${pana_args[@]}" . >"${report}"

# Mirror main is the pre-transfer seed until the owner publishes it; drop this allowance then.
# logto_dart_sdk stays on ^3.0.0 until a reviewed 4.x upgrade; drop this allowance then.
verdict="$(jq -r '
  def seed: .id == "convention" and .maxPoints - .grantedPoints == 10
    and (.summary | [scan("<summary>")] | length) == 1
    and (.summary | test("Failed to verify repository URL[.]"))
    and (.summary | test("but got `https://github[.]com/AtomiCloud/diene[.]dart_auth_engine`"));
  def logto: .id == "dependency" and .maxPoints - .grantedPoints == 10
    and ([.summary | scan("<summary>\\s*([^<]*?)\\s*</summary>") | .[0] | select(. != "Transitive dependencies")]
      == ["The constraint `^3.0.0` on logto_dart_sdk does not support the stable version `4.0.0`."]);
  (.scores.maxPoints - .scores.grantedPoints) as $lost
  | [.report.sections[] | select(.grantedPoints < .maxPoints)] as $failed
  | if $lost == 0 then "perfect"
    elif ($failed | all(seed or logto)) and $lost == 10 * ($failed | length)
    then "allowed: " + ([$failed[] | if seed then "mirror-main-seed" else "logto-sdk-3" end] | join(", "))
    else "lost \($lost): " + ([$failed[] | "\(.id) \(.grantedPoints)/\(.maxPoints)"] | join(", "))
    end' "${report}")"

case "${verdict}" in
perfect) echo "✅ pana score is perfect" ;;
allowed:*) echo "✅ pana score is perfect apart from the ${verdict}" ;;
*)
  jq -r '.report.sections[] | select(.grantedPoints < .maxPoints) | .summary' "${report}" >&2
  echo "❌ pana ${verdict}" >&2
  exit 1
  ;;
esac
