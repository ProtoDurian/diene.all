import type { ProbeDefinition } from "@cyanprint/contracts";

const script = `#!/usr/bin/env bash
set -euo pipefail

git --version
git rev-parse --is-inside-work-tree
treefmt --version
nix fmt --no-write-lock-file -- --no-cache
jq --version
jq -n '1 + 1' | grep -qx 2
yq --version
yq -n '.probe = true' | grep -q 'probe: true'
gomplate --version
test "$(gomplate -i '{{ add 1 1 }}')" = 2
bash --version
test "$(bash -lc 'printf probe')" = probe
cyanprint_version="$(cyanprint --version | awk '{ print $2 }')"
[ -n "$cyanprint_version" ] || { echo "cyanprint --version printed no version" >&2; exit 1; }
cyanprint_path="$(command -v cyanprint)"
printf '%s\n' "$cyanprint_path" | grep -Eq "/nix/store/[^/]*-cyanprint-$cyanprint_version/" || {
  echo "cyanprint reports $cyanprint_version but resolved to $cyanprint_path" >&2
  exit 1
}
cache_dir="$(mktemp -d)"
cyanprint cache inspect --cache-dir "$cache_dir" --json | jq -e '.status == "done" and .action == "inspect"' >/dev/null
`;

const definition: ProbeDefinition = {
  contractVersion: 1,
  sandbox: { snapshot: "git" },
  probes: [
    {
      name: "declared-binary-inventory-operates",
      description:
        "The root package inventory answers version or help and completes representative real operations.",
      kind: "baseline",
      timeoutMs: 240000,
      async run(repo) {
        await repo.write(".probe-binary-smoke.sh", script);
        const result = await repo.exec(
          "nix develop --no-write-lock-file .#default -c bash .probe-binary-smoke.sh",
          { timeoutMs: 240000 },
        );
        if (result.exitCode !== 0) {
          throw new Error(
            `binary smoke failed: ${result.stderr || result.stdout}`,
          );
        }
      },
    },
    {
      name: "workspace-binary-smoke-resolves",
      description:
        "Every binary workspace declares for the default shell resolves in it (dlint toolchain-smoke).",
      kind: "baseline",
      timeoutMs: 240000,
      async run(repo) {
        const result = await repo.exec(
          "nix develop --no-write-lock-file .#default -c dlint toolchain-smoke",
          { timeoutMs: 240000 },
        );
        if (result.exitCode !== 0) {
          throw new Error(
            `workspace toolchain-smoke failed: ${result.stderr || result.stdout}`,
          );
        }
      },
    },
    {
      name: "workspace-binary-smoke-invokes",
      description:
        "Every binary workspace adds answers a real smoke invocation, not just a PATH lookup. The root inventory is the parent probe's.",
      kind: "baseline",
      timeoutMs: 240000,
      async run(repo) {
        // This is a JS template literal, not raw shell. String.raw suppresses ESCAPE
        // processing only; it does not suppress interpolation, so shell variables are
        // written bare ($var). probes/lib/probe-modules.test.ts imports this module.
        const invocations = String.raw`
set -euo pipefail
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

actionlint -version >/dev/null
printf '%s\n' 'name: Smoke' 'on: push' 'jobs:' '  smoke:' '    runs-on: ubuntu-latest' '    steps:' '      - run: echo smoke' >"$tmp/workflow.yaml"
actionlint "$tmp/workflow.yaml"

dlint exec-bits >/dev/null

docker --version >/dev/null
docker info --format '{{.ServerVersion}}' >/dev/null

hadolint --version >/dev/null
hadolint infra/Dockerfile

helm-docs --version >/dev/null
helm-docs --dry-run --chart-search-root infra/root_chart >/dev/null 2>&1

helm version --short >/dev/null
helm template diene-workspace infra/root_chart | kubeconform -strict -summary >/dev/null

infisical --version >/dev/null
git -C "$tmp" init -q
git -C "$tmp" config user.email smoke@example.invalid
git -C "$tmp" config user.name Smoke
touch "$tmp/empty"
git -C "$tmp" add empty
git -C "$tmp" commit -qm smoke
(cd "$tmp" && infisical scan . -v >/dev/null 2>&1)

k3d version >/dev/null
k3d cluster list --no-headers >/dev/null

kubeconform -v >/dev/null

kubectl version --client >/dev/null
kubectl --kubeconfig=/dev/null config view >/dev/null

kyverno version >/dev/null
printf '%s\n' '{"probe":{"ok":true}}' | kyverno jp query 'probe.ok' 2>/dev/null | tail -n 1 | rg -qx true

nix --version >/dev/null
nix flake metadata --no-write-lock-file --json . | jq -e '.url | type == "string"' >/dev/null

pre-commit --version >/dev/null
pre-commit validate-config .pre-commit-config.yaml

releaser_version="$(releaser --version)"
[ "$releaser_version" = "2.0.0" ] || {
  echo "releaser reports $releaser_version; the registry wire requires v2.0.0" >&2
  exit 1
}
releaser_path="$(command -v releaser)"
printf '%s\n' "$releaser_path" | rg -q "/nix/store/[^/]*-releaser-$releaser_version/bin/releaser$" || {
  echo "releaser reports $releaser_version but resolved to $releaser_path" >&2
  exit 1
}
legacy_dir="$tmp/releaser-legacy-config"
mkdir -p "$legacy_dir"
cp release.yaml "$legacy_dir/atomi_release.yaml"
legacy_rc=0
(cd "$legacy_dir" && releaser conventions >legacy-out.txt 2>&1) || legacy_rc=$?
[ "$legacy_rc" = "1" ] || {
  echo "releaser v2 accepted its retired default config name (exit $legacy_rc)" >&2
  exit 1
}
rg -Fxq 'release.yaml not found, but atomi_release.yaml exists. This tool formerly read atomi_release.yaml; rename it to release.yaml (or pass -c atomi_release.yaml to keep the old name).' "$legacy_dir/legacy-out.txt" || {
  echo "releaser v2 refused the retired config name without its migration remedy" >&2
  exit 1
}
printf '%s\n' 'chore: smoke the releaser commit linter' >"$tmp/releaser-msg-ok.txt"
releaser lint-commit "$tmp/releaser-msg-ok.txt" -c release.yaml >/dev/null
printf '%s\n' 'nope: this commit type is not configured' >"$tmp/releaser-msg-bad.txt"
if releaser lint-commit "$tmp/releaser-msg-bad.txt" -c release.yaml >/dev/null 2>&1; then
  echo "releaser lint-commit accepted a commit type that is not in release.yaml" >&2
  exit 1
fi

rg --version >/dev/null
printf '%s\n' 'alpha' 'ripgrep smoke needle' 'omega' >"$tmp/rg-fixture.txt"
rg -q 'ripgrep smoke needle' "$tmp/rg-fixture.txt"
# rg exits 1 for no-match and 2 for error, so only the exact code proves the fixture was read.
rc=0
rg -q 'no-such-needle-should-ever-match' "$tmp/rg-fixture.txt" || rc=$?
[ "$rc" = "1" ] || { echo "rg: expected exit 1 (no match), got $rc" >&2; exit 1; }

shellcheck --version >/dev/null
printf '%s\n' '#!/usr/bin/env bash' 'set -euo pipefail' 'echo "shellcheck smoke"' >"$tmp/shellcheck-clean.sh"
shellcheck "$tmp/shellcheck-clean.sh"
# A clean file exits 0 and so does a shellcheck that inspected nothing, so the green above
# carries no evidence on its own. shellcheck exits 1 for a finding and 2 for a file it could
# not read: only the exact code, plus the code of the finding itself, proves the fixture was
# read. Same reasoning as the rg fixture above.
printf '%s\n' '#!/usr/bin/env bash' 'set -euo pipefail' 'echo $UNQUOTED' >"$tmp/shellcheck-finding.sh"
rc=0
shellcheck "$tmp/shellcheck-finding.sh" >"$tmp/shellcheck-out.txt" 2>&1 || rc=$?
[ "$rc" = "1" ] || { echo "shellcheck: expected exit 1 (finding), got $rc" >&2; exit 1; }
rg -q 'SC2086' "$tmp/shellcheck-out.txt" || { echo "shellcheck: exit 1 without the SC2086 finding" >&2; exit 1; }

skopeo --version >/dev/null
printf '%s\n' '{"schemaVersion":2,"mediaType":"application/vnd.oci.image.manifest.v1+json","config":{"mediaType":"application/vnd.oci.image.config.v1+json","digest":"sha256:44136fa355b3678a1146ad16f7e8649e94fb4fc21fe77e8310c060f61caaff8a","size":2},"layers":[]}' >"$tmp/manifest.json"
skopeo manifest-digest "$tmp/manifest.json" | rg -q '^sha256:[0-9a-f]{64}$'

task --version >/dev/null
task --list >/dev/null

echo "workspace toolchain invocations passed"
`;
        await repo.write("probe-toolchain-invocations.sh", invocations);
        try {
          const result = await repo.exec(
            "nix develop --no-write-lock-file .#default -c bash probe-toolchain-invocations.sh",
            { timeoutMs: 240000 },
          );
          if (result.exitCode !== 0) {
            throw new Error(
              `workspace binary smoke failed: ${result.stderr || result.stdout}`,
            );
          }
        } finally {
          await repo.remove("probe-toolchain-invocations.sh");
        }
      },
    },
  ],
};

export default definition;
