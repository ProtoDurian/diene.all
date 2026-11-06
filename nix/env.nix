{ pkgs, packages }:
with packages;
{
  dev = [
    git
    go-task
    infisical
    releaser
  ];

  lint = [
    actionlint
    dlint
    go-tools
    gofumpt
    golangci-lint
    gotools
    infralint-core
    pre-commit
    shellcheck
    skills-sync
    treefmt
  ];

  main = [
    cyanprint
    git
    go
    gorelease
    go-task
    gotestsum
    govulncheck
    infisical
    releaser
    shellcheck
    zip
  ];

  releaser = [
    releaser
  ];

  system = [
    atomiutils
    infrautils-core
    nix
  ];
}
