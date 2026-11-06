#!/usr/bin/env bash
set -euo pipefail

# The inherited a-wrapper-helm-lint hook calls this path.
exec bash ./scripts/validate/chlorine.sh "$@"
