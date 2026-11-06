#!/usr/bin/env bash
set -euo pipefail

SNAPSHOT=0
[ "${1:-}" = "--snapshot" ] && SNAPSHOT=1

if [ "${SNAPSHOT}" -eq 1 ]; then
  echo "📦 GoReleaser snapshot (no publish) ..."
  goreleaser release --snapshot --clean --skip=publish
  ./scripts/release/smoke.sh dist/aseity_bun-linux-x64-baseline/aseity
  echo "✅ Snapshot complete — artifacts in dist/, nothing was published."
  exit 0
fi

[ -z "${HOMEBREW_TAP_TOKEN:-}" ] && echo "❌ 'HOMEBREW_TAP_TOKEN' env var not set" >&2 && exit 1
[ -z "${SCOOP_BUCKET_TOKEN:-}" ] && echo "❌ 'SCOOP_BUCKET_TOKEN' env var not set" >&2 && exit 1
[ -z "${FURY_TOKEN:-}" ] && echo "❌ 'FURY_TOKEN' env var not set" >&2 && exit 1
[ -z "${GITHUB_TOKEN:-}" ] && echo "❌ 'GITHUB_TOKEN' env var not set" >&2 && exit 1

echo "⚙️ Generating changelog diff ..."
if [ ! -f Changelog.md ] || [ ! -f Changelog.old.md ]; then
  touch IncrementalChangelog.md
else
  set +e
  diff --new-line-format='' --unchanged-line-format='' --old-line-format='%L' Changelog.md Changelog.old.md >IncrementalChangelog.md
  ec="$?"
  set -e
  [ "${ec}" -gt 1 ] && echo "❌ changelog diff failed" >&2 && exit 1
fi

echo "📦 Staging release artifacts without publishing ..."
goreleaser release --clean --skip=publish --release-notes ./IncrementalChangelog.md
./scripts/release/smoke.sh dist/aseity_bun-linux-x64-baseline/aseity

echo "📤 Pushing Debian packages to Gemfury ..."
./scripts/release/fury.sh

echo "📦 GoReleaser release (GitHub release, Homebrew cask, Scoop manifest) ..."
goreleaser release --clean --release-notes ./IncrementalChangelog.md

echo "✅ Release complete."
