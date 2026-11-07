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
    infralint
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
    releaser
  ];

  system = [
    atomiutils
    infrautils
    nix
  ];
}
