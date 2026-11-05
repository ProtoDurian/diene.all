#!/usr/bin/env bash
set -euo pipefail

container="diene-go-base-redis"

existing="$(docker ps --all --quiet --filter "name=^/${container}$")"
[ -z "${existing}" ] && echo "✅ Local dependencies already stopped" && exit 0

docker rm --force "${container}" >/dev/null

echo "✅ Local dependencies stopped"
