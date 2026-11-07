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
    helm-schema
    infralint
    pre-commit
    shellcheck
    skills-sync
    treefmt
  ];

  main = [
    cyanprint
    git
    go-task
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
