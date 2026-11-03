{ pkgs, packages }:
with packages;
{
  dev = [
    git
    go-task
    infisical
    releaser
    dpkg
    gh
    go
    goreleaser
    rpm
  ];

  lint = [
    actionlint
    dlint
    infralint-core
    infralint-docker
    pre-commit
    shellcheck
    skills-sync
    treefmt
  ];

  main = [
    bun
    cyanprint
    git
    go-task
    infisical
    nodejs
    releaser
    shellcheck
  ];

  releaser = [
    dpkg
    gh
    git
    go
    goreleaser
    rpm
    releaser
  ];

  system = [
    atomiutils
    infrautils-core
    infrautils-docker
    nix
  ];
}
