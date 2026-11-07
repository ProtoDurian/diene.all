#!/usr/bin/env bash
set -euo pipefail

# Files only (owner !A103): the nix bundles legitimately put docker/helm on PATH.

cd "$(git rev-parse --show-toplevel)"
# index tree == HEAD in CI; keeps local staged mutations visible
tree="$(git write-tree)"
work="$(mktemp -d)"
trap 'rm -rf "${work}"' EXIT
failed=0

fail() {
  echo "❌ $*" >&2
  failed=1
}

D_PATHS=(
  infra
  .dockerignore
  '.github/workflows/⚡reusable-docker.yaml'
  tasks/Taskfile.docker.yaml
  scripts/ci/docker.sh
  .claude/skills/docker-push
  docs/standards/docker
  probes/docker-build.ts
)
H_PATHS=(
  '.github/workflows/⚡reusable-helm.yaml'
  tasks/Taskfile.helm.yaml
  scripts/ci/helm.sh
  .claude/skills/helm-push
  docs/standards/helm
  probes/helm-lint.ts
  probes/helm-render.ts
  probes/hook-helm-lint.ts
  .helmignore
)
DH_TOKENS=(
  infra/Dockerfile .dockerignore reusable-docker Taskfile.docker docker.sh
  docker-push standards/docker docker/index.md docker-build
  root_chart reusable-helm Taskfile.helm helm.sh helm-push standards/helm
  helm/index.md a-helm-lint helm-lint helm-render
  '](infra)' 'infra/' 'docker:build' 'docker:run'
)
SCAN_EXEMPT=(':!.github/named-checks/**' ':!Changelog.md' ':!probes/lib/**')
# Any tracked D/H file wherever it lives, not only the parent's former paths.
DH_FILE_RE='(^|/)(Dockerfile|Containerfile)([._-][^/]*)?$|\.(dockerfile|containerfile)$|(^|/)\.(docker|helm)ignore$|(^|/)(docker-)?compose([._-][^/]*)?\.ya?ml$|(^|/)Chart\.(yaml|lock)$|(^|/)helmfile[^/]*$|(^|/)(charts|root_chart)/|(^|/)skaffold[^/]*\.ya?ml$'
DH_SURFACE_RE='^(\.github/workflows|\.github/actions|scripts|tasks|probes|nix|\.claude/skills|docs/standards)/([^/]*/)*[^/]*(docker|helm|compose|container|chart)[^/]*$'

F_PATH_RE='(^|/)(android|ios|macos|linux|windows|web|gradle|Pods)/|\.(xcodeproj|xcworkspace)/|(^|/)(build|settings)\.gradle(\.kts)?$|(^|/)(gradle\.properties|gradlew|gradlew\.bat|local\.properties|Podfile|Podfile\.lock|AndroidManifest\.xml|\.metadata|\.flutter-plugins|\.flutter-plugins-dependencies)$|\.(gradle|gradle\.kts|podspec|xcconfig|pbxproj|storyboard|xib|entitlements)$'
F_IMPORT_RE="['\"](package:flutter[a-z0-9_]*/|dart:ui['\"])"
F_TOOL_RE='flutter|gradle|gradlew|cocoapods|pod install|xcodebuild|xcrun|xcode|sdkmanager|avdmanager|emulator|androidenv|android-sdk|android_sdk|androidsdk|android-tools|subosito'
F_TOOL_FILES=(.github/workflows scripts tasks Taskfile.yaml nix flake.nix .envrc dlint.yaml probes ':!probes/lib/**')

flutter_paths() { grep -E "${F_PATH_RE}" || true; }
dh_files() {
  local in
  in="$(cat)"
  {
    grep -E "${DH_FILE_RE}" <<<"${in}" || true
    grep -i -E "${DH_SURFACE_RE}" <<<"${in}" || true
  } | grep -v '^\.github/named-checks/' | LC_ALL=C sort -u || true
}
flutter_pubspec() { yq '[has("flutter"), (.environment // {} | has("flutter"))] + ([(.dependencies // {}), (.dev_dependencies // {}), (.dependency_overrides // {})] | map(to_entries) | flatten | map((.key | test("^flutter")) or ((.value | tag) == "!!map" and (.value.sdk // "") == "flutter"))) | map(select(.)) | length'; }
flutter_imports() { grep -E "${F_IMPORT_RE}" || true; }
# pkgs.flutter.dart is nixpkgs' plain Dart SDK attribute, not the Flutter SDK.
flutter_tools() { sed -E 's/flutter\.dart([^A-Za-z0-9_]|$)/\1/g' | grep -i -E "(^|[^A-Za-z0-9_-])(${F_TOOL_RE})([^A-Za-z0-9_-]|$)" || true; }

# --- positive control: each detector fires on a canary, and the scan sees the real tree ---
[[ -n "$(printf 'android/app/build.gradle\nios/Podfile\n' | flutter_paths)" ]] || fail "control: the platform-path detector misses a canary"
[[ "$(printf 'dependencies:\n  flutter:\n    sdk: flutter\n' | flutter_pubspec)" -ge 1 ]] || fail "control: the pubspec detector misses a canary"
[[ "$(printf 'name: x\ndependencies: {}\n' | flutter_pubspec)" == 0 ]] || fail "control: the pubspec detector flags a clean pubspec"
[[ -n "$(echo "import 'package:flutter/material.dart';" | flutter_imports)" ]] || fail "control: the import detector misses a canary"
[[ -n "$(echo 'run: flutter build apk' | flutter_tools)" ]] || fail "control: the tooling detector misses a canary"
[[ -z "$(echo 'dart = flutter.dart;' | flutter_tools)" ]] || fail "control: the tooling detector flags the plain Dart SDK attribute"
for c in Dockerfile services/api/Dockerfile.prod deploy/web.containerfile Containerfile .dockerignore docker-compose.yml compose.yaml ops/charts/app/Chart.yaml deploy/Chart.lock helmfile.yaml '.github/workflows/⚡reusable-docker-build.yaml' scripts/ci/helm-publish.sh tasks/Taskfile.compose.yaml; do
  dh_files <<<"${c}" | grep -q . || fail "control: the D/H file detector misses ${c}"
done
for c in pubspec.yaml packages/diene_dart_lib/lib/src/note.dart docs/standards/ci-cd/index.md .github/workflows/ci.yaml scripts/ci/test.sh; do
  dh_files <<<"${c}" | grep -q . && fail "control: the D/H file detector flags ${c}"
done

git -c core.quotePath=false ls-tree -r --name-only "${tree}" >"${work}/files"
mapfile -t pubspecs < <(grep -E '(^|/)pubspec\.yaml$' "${work}/files" || true)
mapfile -t dart_files < <(grep -E '\.dart$' "${work}/files" || true)
[[ " ${pubspecs[*]} " == *" pubspec.yaml "* && " ${pubspecs[*]} " == *" packages/diene_dart_lib/pubspec.yaml "* ]] || fail "control: the scan does not see the root and member pubspec.yaml (${pubspecs[*]:-none})"
[[ ${#dart_files[@]} -ge 5 ]] || fail "control: the scan sees only ${#dart_files[@]} Dart files"
grep -qx 'nix/packages.nix' "${work}/files" || fail "control: the scan does not see nix/packages.nix"

# --- Docker / Helm: paths, references, anchored entries -------------------------------
for p in "${D_PATHS[@]}"; do
  if [[ -n "$(git ls-tree --name-only "${tree}" -- "${p}")" ]]; then fail "D path tracked: ${p}"; fi
done
for p in "${H_PATHS[@]}"; do
  if [[ -n "$(git ls-tree --name-only "${tree}" -- "${p}")" ]]; then fail "H path tracked: ${p}"; fi
done
hits="$(dh_files <"${work}/files")"
[[ -z ${hits} ]] || fail "D/H axis files tracked:"$'\n'"${hits}"

args=()
for t in "${DH_TOKENS[@]}"; do args+=(-e "${t}"); done
hits="$(git -c core.quotePath=false grep -n -F "${args[@]}" "${tree}" -- . "${SCAN_EXEMPT[@]}" || true)"
[[ -z ${hits} ]] || fail "files reference removed D/H paths:"$'\n'"${hits}"

show() { git show "${tree}:$1"; }
for wf in .github/workflows/ci.yaml .github/workflows/cd.yaml; do
  [[ "$(show "${wf}" | yq '[.jobs[] | select(.uses // "" | test("docker|helm"))] | length')" == 0 ]] || fail "${wf} calls a docker/helm workflow"
  [[ "$(show "${wf}" | yq '[.jobs | keys | .[] | select(test("docker|helm"))] | length')" == 0 ]] || fail "${wf} has a docker/helm job"
done
[[ "$(show .github/workflows/cd.yaml | yq '.jobs | keys | sort | join(",")')" == publish,release ]] || fail "cd.yaml jobs are not exactly release + publish"
[[ "$(show .github/workflows/cd.yaml | yq '[.jobs.release.uses, .jobs.publish.uses] | join(",")')" == "./.github/workflows/⚡reusable-release-note.yaml,./.github/workflows/⚡reusable-publish.yaml" ]] || fail "cd.yaml release/publish jobs do not call the release-note/publish workflows"
[[ "$(show .github/workflows/cd.yaml | yq -o=json -I=0 '[(.on | keys), (.on.push | keys)]')" == '[["push","workflow_dispatch"],["tags"]]' ]] || fail "cd.yaml triggers are not exactly tag pushes + workflow_dispatch"
parent_sha="$(cat .github/named-checks/dart-lib/parent.sha)"
git rev-parse --verify --quiet "${parent_sha}^{commit}" >/dev/null || git fetch --quiet --no-tags origin "${parent_sha}" || true
git rev-parse --verify --quiet "${parent_sha}^{commit}" >/dev/null || { echo "❌ shared-wo-docker-helm .3 commit ${parent_sha} not found; fetch it first" >&2 && exit 1; }
[[ "$(show .github/workflows/cd.yaml | yq -o=json -I=0 .jobs.release)" == "$(git show "${parent_sha}:.github/workflows/cd.yaml" | yq -o=json -I=0 .jobs.release)" ]] || fail "cd.yaml release job differs from the parent's"
for f in '.github/workflows/⚡reusable-release-note.yaml' scripts/ci/release-note.sh; do
  [[ "$(git rev-parse "${tree}:${f}")" == "$(git rev-parse "${parent_sha}:${f}")" ]] || fail "${f} differs from the parent's"
done
[[ "$(show Taskfile.yaml | yq '.includes // {} | (has("docker") or has("helm"))')" == false ]] || fail "Taskfile.yaml includes docker/helm"
[[ "$(show .github/dependabot.yml | yq '[.updates[] | select(.package-ecosystem == "docker" or .package-ecosystem == "helm")] | length')" == 0 ]] || fail "dependabot.yml has a docker/helm entry"
[[ "$(show probes/features.json | jq '[.[] | select(.name | test("docker|helm"))] | length')" == 0 ]] || fail "features.json has a docker/helm row"
if show CLAUDE.md | grep -Eqi '^# (docker|helm)'; then fail "CLAUDE.md has a Docker/Helm section"; fi
if show nix/pre-commit.nix | grep -Eq 'helm|hadolint'; then fail "nix/pre-commit.nix has a docker/helm hook"; fi

# --- Flutter / Android / Gradle / CocoaPods / Xcode surface ---------------------------
hits="$(flutter_paths <"${work}/files")"
[[ -z ${hits} ]] || fail "platform/mobile project files tracked:"$'\n'"${hits}"

for p in "${pubspecs[@]}"; do
  n="$(show "${p}" | flutter_pubspec 2>"${work}/yq.err")" || { fail "${p} does not parse: $(head -3 "${work}/yq.err")" && continue; }
  [[ ${n} == 0 ]] || fail "${p} declares a Flutter SDK, key or dependency"
done

hits="$(git -c core.quotePath=false grep -n -I -E "${F_IMPORT_RE}" "${tree}" -- '*.dart' || true)"
[[ -z ${hits} ]] || fail "Dart sources import Flutter or dart:ui:"$'\n'"${hits}"
hits="$(git -c core.quotePath=false grep -n -I -i -E 'flutter' "${tree}" -- '*analysis_options*.yaml' || true)"
[[ -z ${hits} ]] || fail "analysis options pull Flutter lints:"$'\n'"${hits}"

hits="$(git -c core.quotePath=false grep -n -I -i -E "${F_TOOL_RE}" "${tree}" -- "${F_TOOL_FILES[@]}" | flutter_tools || true)"
[[ -z ${hits} ]] || fail "CI/scripts/tasks/nix name mobile tooling:"$'\n'"${hits}"

if [[ ${failed} -ne 0 ]]; then
  exit 1
fi

echo "✅ stripped-axis-absence: no D/H path, reference or entry (cd.yaml is release + publish); no Flutter/Android/Gradle/CocoaPods/Xcode surface across ${#pubspecs[@]} pubspecs and ${#dart_files[@]} Dart files"
