#!/usr/bin/env bash
set -euo pipefail

version="${1:-}"
[ -z "${version}" ] && echo "❌ version argument not set" >&2 && exit 1
git restore --source=HEAD -- Version.props
[ "$(xmlstarlet select --template --value-of 'count(/Project/PropertyGroup/Version)' Version.props)" != "1" ] && echo "❌ Version.props must contain exactly one Version element" >&2 && exit 1

xmlstarlet ed --omit-decl --inplace \
  --update '/Project/PropertyGroup/Version' \
  --value "${version#v}" \
  Version.props

echo "✅ Version.props stamped to ${version#v}"
