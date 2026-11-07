#!/usr/bin/env bash
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${here}/cluster-name.sh"

id_a="$(e2e_invocation_id "/same/worktree" 1000)"
id_b="$(e2e_invocation_id "/same/worktree" 2000)"
id_c="$(e2e_invocation_id "/same/worktree" 1000)"
[ "${id_a}" != "${id_b}" ] || {
  echo "❌ invocation IDs collided: ${id_a}" >&2
  exit 1
}
[ "${id_a}" = "${id_c}" ] || {
  echo "❌ invocation ID not deterministic: ${id_a} vs ${id_c}" >&2
  exit 1
}
echo "✅ invocation IDs are unique and deterministic"

got="$(e2e_cluster_name "my-fixed-cluster" "${id_a}")"
[ "${got}" = "my-fixed-cluster" ] || {
  echo "❌ override not preserved: ${got}" >&2
  exit 1
}
got_image="$(e2e_image_name "registry.example/manager:fixed" "${id_a}")"
[ "${got_image}" = "registry.example/manager:fixed" ] || {
  echo "❌ image override not preserved: ${got_image}" >&2
  exit 1
}
echo "✅ resource overrides preserved"

a="$(e2e_cluster_name "" "${id_a}")"
b="$(e2e_cluster_name "" "${id_b}")"
[ "${a}" != "${b}" ] || {
  echo "❌ default names collided across invocations: ${a}" >&2
  exit 1
}
image_a="$(e2e_image_name "" "${id_a}")"
image_b="$(e2e_image_name "" "${id_b}")"
[ "${image_a}" != "${image_b}" ] || {
  echo "❌ default image names collided: ${image_a}" >&2
  exit 1
}
echo "✅ default resource names unique per invocation"

for name in "${a}" "${b}"; do
  [[ ${name} =~ ^[a-z0-9]([a-z0-9-]*[a-z0-9])?$ ]] || {
    echo "❌ name not k3d-safe: ${name}" >&2
    exit 1
  }
  [ "${#name}" -le 32 ] || {
    echo "❌ name too long for k3d: ${name}" >&2
    exit 1
  }
done
echo "✅ defaults are k3d-safe"

[[ ${image_a} =~ ^operator-template:e2e-[a-f0-9]{16}$ ]] || {
  echo "❌ default image name is unsafe: ${image_a}" >&2
  exit 1
}
echo "✅ default image name is Docker-safe"

echo "✅ e2e cluster-name helper regression checks passed"
