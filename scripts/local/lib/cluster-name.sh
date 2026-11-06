#!/usr/bin/env bash
# shellcheck shell=bash

e2e_invocation_id() {
  local digest
  digest="$(printf '%s:%s' "${1:-}" "${2:-}" | sha256sum | cut -c1-16)"
  printf '%s' "${digest}"
}

# k3d caps cluster names at 32 characters.
e2e_cluster_name() {
  local override="${1:-}"
  [ -n "${override}" ] && printf '%s' "${override}" && return 0
  printf 'operator-e2e-%s' "${2:-}"
}

e2e_image_name() {
  local override="${1:-}"
  [ -n "${override}" ] && printf '%s' "${override}" && return 0
  printf 'operator-template:e2e-%s' "${2:-}"
}
