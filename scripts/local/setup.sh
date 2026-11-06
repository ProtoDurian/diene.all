#!/usr/bin/env bash
set -euo pipefail

root_dir="$(git rev-parse --show-toplevel)"
cd "${root_dir}"

releaser conventions -c release.yaml
skills-sync sync

echo "🔧 Restoring .NET tools and packages..."
dotnet tool restore
dotnet restore dotnet-base.slnx

echo "✅ setup completed"
