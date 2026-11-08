#!/usr/bin/env bash
set -euo pipefail

root_dir="$(git rev-parse --show-toplevel)"
member_dir="${root_dir}/${MEMBER_DIR:-packages/diene_dart_lib}"
cd "${member_dir}"

name="$(yq -r '.name' pubspec.yaml)"
sdk="$(yq -r '.environment.sdk' pubspec.yaml)"
version="$(yq -r '.version' pubspec.yaml)-consumer"
user_cache="${PUB_CACHE:-${HOME}/.pub-cache}"

work="$(mktemp -d)"
trap 'rm -rf "${work}"' EXIT
archive="${work}/package.tar.gz"
installable="${work}/installable.tar.gz"
unpacked="${work}/package"
consumer="${work}/consumer"
export PUB_CACHE="${work}/pub-cache"
mkdir -p "${unpacked}" "${consumer}/bin" "${PUB_CACHE}/hosted/pub.dev" "${PUB_CACHE}/hosted-hashes/pub.dev"

echo "📦 Packing ${name} with pub..."
dart pub publish --skip-validation --to-archive="${archive}"
tar -xzf "${archive}" -C "${unpacked}"

echo "🔎 Comparing the archive with the package's committed files minus .pubignore and pub's defaults..."
git ls-tree -r --name-only HEAD | awk -F/ '
  { for (i = 1; i <= NF; i++) if ($i ~ /^[.]/ && $i != ".htaccess") next }
  /(^|\/)pubspec[.]lock$/ || /^pubspec_overrides[.]yaml$/ { next }
  { print }' | LC_ALL=C sort >"${work}/committed"
git ls-files -c -i --exclude-per-directory=.pubignore | LC_ALL=C sort >"${work}/ignored"
LC_ALL=C comm -23 "${work}/committed" "${work}/ignored" >"${work}/expected"
(cd "${unpacked}" && find . -type f | sed 's|^\./||' | LC_ALL=C sort) >"${work}/shipped"
if ! diff -u --label expected --label archive "${work}/expected" "${work}/shipped" >&2; then
  echo "❌ the archive does not match the package's committed files minus .pubignore (an uncommitted file also fails)" >&2
  exit 1
fi

mapfile -t libraries < <(cd "${unpacked}/lib" && find . -maxdepth 1 -type f -name '*.dart' | sed 's|^\./||' | LC_ALL=C sort)
[[ ${#libraries[@]} -eq 0 ]] && echo "❌ the archive ships no public lib/*.dart library" >&2 && exit 1

echo "📥 Installing the local archive (as ${version}) into an isolated pub cache..."
# pub hides version 0.0.0 from offline resolution: only the archive's version field is rewritten.
yq -i ".version = \"${version}\"" "${unpacked}/pubspec.yaml"
tar -czf "${installable}" -C "${unpacked}" .
for entry in "${user_cache}"/hosted/pub.dev/* "${user_cache}"/hosted-hashes/pub.dev/*; do
  if [[ -e ${entry} ]]; then ln -s "${entry}" "${PUB_CACHE}/${entry#"${user_cache}/"}"; fi
done
dart pub cache preload "${installable}"

cat >"${consumer}/pubspec.yaml" <<YAML
name: consumer_fixture
publish_to: none
environment:
  sdk: '${sdk}'
dependencies:
  ${name}: ${version}
YAML
cat >"${consumer}/analysis_options.yaml" <<'YAML'
analyzer:
  language:
    strict-casts: true
    strict-inference: true
    strict-raw-types: true
YAML
{
  echo '// ignore_for_file: unused_import'
  for library in "${libraries[@]}"; do echo "import 'package:${name}/${library}';"; done
  echo 'void main() {}'
} >"${consumer}/bin/libraries.dart"
cat >"${consumer}/bin/consumer.dart" <<DART
import 'package:${name}/diene_dart_lib.dart';

void main() {
  const Note note = Note(title: 'Consumer', body: 'Installed from the archive.');
  final Note decoded = Note.fromJson(note.toJson());
  if (decoded != note) throw StateError('the wire codec did not round-trip');
  final String summary = summarizeNote(note);
  if (summary != 'Consumer — Installed from the archive.') throw StateError('unexpected summary: \$summary');
  print('consumer: \$summary');
}
DART
if [[ -f lib/test_helper.dart ]]; then
  cat >"${consumer}/bin/test_helper.dart" <<DART
import 'package:${name}/diene_dart_lib.dart';
import 'package:${name}/test_helper.dart';

void main() {
  const Note note = Note(title: 'Consumer', body: 'Helper.');
  assertNoteSummary(note, summarizeNote(note));
}
DART
fi

cd "${consumer}"
dart pub get --offline
root_uri="$(jq -r --arg n "${name}" '.packages[] | select(.name == $n) | .rootUri' .dart_tool/package_config.json)"
[[ ${root_uri} != "file://${PUB_CACHE}/hosted/pub.dev/${name}-${version}" ]] && echo "❌ ${name} resolved to ${root_uri}, not the preloaded archive" >&2 && exit 1

echo "🔎 Importing every public library (${libraries[*]}), running, compiling and type-checking..."
for entry in bin/*.dart; do dart run "${entry}"; done
dart compile exe bin/consumer.dart -o "${work}/consumer.exe"
"${work}/consumer.exe"
dart analyze --fatal-infos

echo "✅ consumer test: ${name} packs, installs from the local archive, imports, runs, compiles and type-checks"
