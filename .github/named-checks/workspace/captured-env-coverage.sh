#!/usr/bin/env bash
set -euo pipefail

nix shell --inputs-from . nixpkgs#bun -c bun test probes/lib/captured-env-coverage.test.ts
