#!/usr/bin/env bash
set -euo pipefail

# Consumer tier: pack with pub, install the local archive in a fresh project, import, run, compile, type-check.
# Expected files = tracked minus .pubignore; import specs = the archive's top-level lib/*.dart.

root_dir="$(git rev-parse --show-toplevel)"
member_dir="${root_dir}/${MEMBER_DIR:-packages/diene_dart_lib}"
cd "${member_dir}"

name="$(yq -r '.name' pubspec.yaml)"
sdk="$(yq -r '.environment.sdk' pubspec.yaml)"

work="$(mktemp -d)"
trap 'rm -rf "${work}"' EXIT
archive="${work}/package.tar.gz"
unpacked="${work}/package"
consumer="${work}/consumer"
mkdir -p "${unpacked}" "${consumer}/bin"

echo "📦 Packing ${name} with pub..."
dart pub publish --skip-validation --to-archive="${archive}"
tar -xzf "${archive}" -C "${unpacked}"

echo "🔎 Comparing the archive with the package's tracked files minus .pubignore..."
# pub never ships dotfiles.
git ls-files -c | grep -Ev '(^|/)[.]' | LC_ALL=C sort >"${work}/tracked"
git ls-files -c -i --exclude-per-directory=.pubignore | LC_ALL=C sort >"${work}/ignored"
LC_ALL=C comm -23 "${work}/tracked" "${work}/ignored" >"${work}/expected"
(cd "${unpacked}" && find . -type f | sed 's|^\./||' | LC_ALL=C sort) >"${work}/shipped"
if ! diff -u --label expected --label archive "${work}/expected" "${work}/shipped" >&2; then
  echo "❌ the archive does not match the package's tracked files minus .pubignore" >&2
  exit 1
fi

mapfile -t libraries < <(cd "${unpacked}/lib" && find . -maxdepth 1 -type f -name '*.dart' | sed 's|^\./||' | LC_ALL=C sort)
[[ ${#libraries[@]} -eq 0 ]] && echo "❌ the archive ships no public lib/*.dart library" >&2 && exit 1

cat >"${consumer}/pubspec.yaml" <<YAML
name: consumer_fixture
publish_to: none
environment:
  sdk: '${sdk}'
dependencies:
  ${name}:
    path: ${unpacked}
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
import 'package:${name}/test_helper.dart';

void main() {
  const Note note = Note(title: 'Consumer', body: 'Installed from the archive.');
  final Note decoded = Note.fromJson(note.toJson());
  if (decoded != note) throw StateError('the wire codec did not round-trip');
  final String summary = summarizeNote(note);
  assertNoteSummary(note, summary);
  print('consumer: \$summary');
}
DART

cd "${consumer}"
echo "📥 Installing the local archive into a fresh project..."
dart pub get --offline

echo "🔎 Importing every public library (${libraries[*]}), running, compiling and type-checking..."
dart run bin/libraries.dart
dart run bin/consumer.dart
dart compile exe bin/consumer.dart -o "${work}/consumer.exe"
"${work}/consumer.exe"
dart analyze --fatal-infos

echo "✅ consumer test: ${name} packs, installs from the local archive, imports, runs, compiles and type-checks"
