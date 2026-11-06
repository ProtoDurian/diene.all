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
