#!/usr/bin/env bash
set -euo pipefail

# A library has no main package; production reachability is what a consumer of the public API reaches.
runner="$(mktemp -d ./deadcode-runner.XXXXXX)"
trap 'rm -rf "${runner}"' EXIT
cp tests/fixtures/deadcode-consumer.go.txt "${runner}/main.go"

"$@"
