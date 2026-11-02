#!/usr/bin/env bash
set -euo pipefail

root_dir="$(git rev-parse --show-toplevel)"
cd "${root_dir}"

releaser conventions -c release.yaml
skills-sync sync

echo "🔧 Restoring repo-local .NET tools..."
dotnet tool restore

echo "✅ setup completed"
