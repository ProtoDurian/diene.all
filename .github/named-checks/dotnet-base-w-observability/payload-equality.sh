#!/usr/bin/env bash
. "$(git rev-parse --show-toplevel)/.github/named-checks/observability/lib/fold-checks.sh"
payload_equality dotnet-base-w-observability dotnet-base
