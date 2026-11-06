{ pkgs, packages }:
with packages;
{
  dev = [
    prometheus.cli
    git
    go-task
    infisical
    releaser
  ];

  lint = [
    dashboard-linter
    actionlint
    dlint
    go-tools
    gofumpt
    golangci-lint
    gotools
    infralint
    pre-commit
    shellcheck
    skills-sync
    treefmt
  ];

  main = [
    cyanprint
    git
    go
    go-task
    gotestsum
    govulncheck
    infisical
    releaser
    shellcheck
  ];

  releaser = [
    releaser
  ];

  system = [
    atomiutils
    infrautils
    nix
  ];
}
