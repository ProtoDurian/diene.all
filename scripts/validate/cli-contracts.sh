#!/usr/bin/env bash
set -euo pipefail

contract="${1:-}"
[ -z "${contract}" ] && echo "❌ usage: $0 <contract>" >&2 && exit 2

case "${contract}" in
arch)
  test -f bin/releaser.ts
  test -f src/lib/release/ports.ts
  test -f src/adapters/terminal/console-io.ts
  rg -q 'console\.|process\.(stdin|stdout|stderr|exitCode)|from .commander.' src/lib && echo '❌ terminal or CLI IO leaked into src/lib' >&2 && exit 1
  rg -q "from ['\"](\\.\\./)+adapters(?:/|['\"])" src/lib && echo '❌ src/lib imports an adapter (forbidden upward dependency)' >&2 && exit 1
  ;;
release-backup-order)
  yq -o=json '.' release.yaml | jq -e '
    .release.hooks.prepare[0].phase == "beforeWrite" and
    .release.hooks.prepare[0].command == "./scripts/release/backup-changelog.sh" and
    .release.github == false'
  ;;
changelog-asset)
  test -f Changelog.old.md
  yq -o=json '.' release.yaml | jq -e '
    .release.commit.assets | index("Changelog.old.md") != null'
  rg -F -- '--release-notes ./IncrementalChangelog.md' scripts/release/publish.sh
  ;;
release-artifacts)
  yq -o=json '.' .goreleaser.yaml | jq -e '
    (.archives | length) > 0 and
    (.checksum.name_template | length) > 0 and
    ([.release.extra_files[].glob] | index("scripts/release/install.sh") != null)'
  ;;
nfpms)
  yq -o=json '.' .goreleaser.yaml | jq -e '
    [.nfpms[].formats[]] as $formats |
    ($formats | index("deb") != null) and ($formats | index("rpm") != null)'
  ;;
homebrew-cask)
  yq -o=json '.' .goreleaser.yaml | jq -e '
    (.homebrew_casks | length) > 0 and
    ([.homebrew_casks[].hooks.post.install] | join("\n") | contains("com.apple.quarantine"))'
  ;;
fury-wiring)
  yq -o=json '.' .github/workflows/cd.yaml | jq -e '.jobs.goreleaser.uses == "./.github/workflows/⚡reusable-goreleaser.yaml"'
  rg -F './scripts/ci/publish.sh' .github/workflows/⚡reusable-goreleaser.yaml
  rg -F './scripts/release/publish.sh' scripts/ci/publish.sh
  rg -F './scripts/release/fury.sh' scripts/release/publish.sh
  stage_line="$(rg -nF 'goreleaser release --clean --skip=publish --release-notes ./IncrementalChangelog.md' scripts/release/publish.sh | cut -d: -f1)"
  fury_line="$(rg -nF './scripts/release/fury.sh' scripts/release/publish.sh | cut -d: -f1)"
  publish_line="$(rg -nF 'goreleaser release --clean --release-notes ./IncrementalChangelog.md' scripts/release/publish.sh | cut -d: -f1)"
  [ "${stage_line}" -lt "${fury_line}" ] && [ "${fury_line}" -lt "${publish_line}" ] || {
    echo '❌ packages must be staged and sent to Gemfury before GoReleaser publishes GitHub + cask' >&2
    exit 1
  }
  rg -F -- '--config "${credential_config}"' scripts/release/fury.sh
  ! rg -F '${FURY_TOKEN}@' scripts/release/fury.sh
  ;;
changelog-format)
  for required in prettier diff; do
    command -v "${required}" >/dev/null 2>&1 || {
      echo "❌ ${required} is not available, so this check cannot run" >&2
      exit 1
    }
  done
  tmp="$(mktemp -d)"
  before="$(mktemp -d)"
  trap 'rm -rf "${tmp}" "${before}"' EXIT
  # Control: the formatter must rewrite this, or every "unchanged" below proves nothing.
  printf '#   Bad   Spacing\n\n\n\ntext   here\n' >"${tmp}/control.md"
  cp tests/fixtures/golden/*-notes.md "${tmp}/"
  cp "${tmp}"/*.md "${before}/"
  prettier --write "${tmp}"/*.md >/dev/null 2>&1 || true
  diff -q "${before}/control.md" "${tmp}/control.md" >/dev/null 2>&1 && echo '❌ the formatter did not rewrite the control' >&2 && exit 1
  for generated in "${tmp}"/*-notes.md; do
    name="$(basename "${generated}")"
    diff -q "${before}/${name}" "${generated}" >/dev/null 2>&1 || {
      echo "❌ generated changelog notes are not formatter-stable: ${name}" >&2
      diff "${before}/${name}" "${generated}" >&2 | head -10
      exit 1
    }
  done
  ;;
installer-checksum)
  rg -F 'checksums.txt' scripts/release/install.sh
  rg -e 'sha256sum -c|shasum -a 256' scripts/release/install.sh
  ;;
installer-timeouts)
  curl_lines="$(rg '^[[:space:]]*curl ' scripts/release)"
  [ -z "${curl_lines}" ] && echo "❌ no release curl commands found" >&2 && exit 1
  bad_lines="$(printf '%s\n' "${curl_lines}" | awk '!/--connect-timeout/ || !/--max-time/')"
  [ -n "${bad_lines}" ] && printf '❌ curl missing timeout guard:\n%s\n' "${bad_lines}" >&2 && exit 1
  ;;
installation-parity)
  rg -F 'scripts/release/install.sh' .goreleaser.yaml
  rg -F "name_template: '{{ .ProjectName }}_{{ .Os }}_{{ .Arch }}'" .goreleaser.yaml
  rg -F 'checksums.txt' .goreleaser.yaml
  rg -F 'releaser_<os>_<arch>.tar.gz' INSTALLATION.md
  ;;
nix-release-wiring)
  rg -F 'releaser = atomiLib.buildBunCli' nix/packages.nix
  yq -o=json '.' .github/workflows/cd.yaml | jq -e '.jobs.goreleaser.uses == "./.github/workflows/⚡reusable-goreleaser.yaml"'
  rg -F 'nix build .#releaser' .github/workflows/⚡reusable-goreleaser.yaml
  ;;
*)
  echo "❌ unknown CLI contract: ${contract}" >&2
  exit 2
  ;;
esac

echo "✅ CLI contract passed: ${contract}"
