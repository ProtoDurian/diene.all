#!/usr/bin/env bash
set -euo pipefail

root_dir="$(git rev-parse --show-toplevel)"
cd "${root_dir}"

skills-sync sync

echo "✅ setup completed"
