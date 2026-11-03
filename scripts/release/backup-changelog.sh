#!/usr/bin/env bash
set -euo pipefail

cp Changelog.md Changelog.old.md 2>/dev/null || touch Changelog.old.md
echo "✅ Changelog baseline saved to Changelog.old.md"
