import { expectGreen } from './lib/go.ts';

// String.raw still interpolates: write shell variables as $var, never ${var}.
const script = String.raw`
set -euo pipefail
tmp="$(mktemp -d)"
trap 'chmod -R u+w "$tmp"; rm -rf "$tmp"' EXIT
cd "$tmp"
printf 'module example.invalid/inventory\n\ngo 1.26.0\n' >go.mod
printf 'package inventory\n\n// Answer is the inventory smoke value.\nfunc Answer() int { return 42 }\n' >inventory.go
printf 'package inventory_test\n\nimport (\n\t"testing"\n\n\t"example.invalid/inventory"\n)\n\nfunc TestAnswer(t *testing.T) {\n\tif inventory.Answer() != 42 {\n\t\tt.Fatal("wrong answer")\n\t}\n}\n' >inventory_test.go
go build ./...
go vet ./...
gotestsum --format pkgname -- ./... >/dev/null
gofumpt -l . | (! grep .)
staticcheck ./...
deadcode -test ./... | (! grep .)
govulncheck -version >/dev/null
golangci-lint version >/dev/null
gorelease -base=none -version=v0.1.0 | grep -q 'v0.1.0 is a valid semantic version'
zip -q inventory.zip go.mod && zip -sf inventory.zip | grep -q go.mod
echo "go-lib toolchain invocations passed"
`;

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-go-lib-binary-inventory-green',
      description: 'The Go and library tools of the ci shell perform a real invocation each.',
      kind: 'baseline',
      async run(repo: any) {
        await repo.write('.probe-go-lib-inventory.sh', script);
        try {
          await expectGreen(repo, 'nix develop .#ci -c bash .probe-go-lib-inventory.sh', 'go-lib-binary-inventory');
        } finally {
          await repo.remove('.probe-go-lib-inventory.sh');
        }
      },
    },
  ],
};
