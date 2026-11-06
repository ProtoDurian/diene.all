#!/usr/bin/env bash
. "$(git rev-parse --show-toplevel)/.github/named-checks/observability/lib/fold-checks.sh"
payload_equality bun-base-wo-helm-docker-w-observability bun-base-wo-helm-docker
