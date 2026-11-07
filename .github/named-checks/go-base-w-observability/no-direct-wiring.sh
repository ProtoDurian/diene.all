#!/usr/bin/env bash
. "$(git rev-parse --show-toplevel)/.github/named-checks/observability/lib/fold-checks.sh"
no_direct_wiring go-base-w-observability go-base
