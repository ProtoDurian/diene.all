#!/usr/bin/env bash
set -euo pipefail

root_dir="$(git rev-parse --show-toplevel)"
cd "${root_dir}"

bun install --frozen-lockfile

echo "🧪 Running the SIT tier: real OTLP http/protobuf export to a loopback receiver..."
bun test --config=bunfig.sit.toml

echo "✅ SIT tests passed"
