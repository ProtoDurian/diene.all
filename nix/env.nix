{ pkgs, packages }:
with packages;
{
  dev = [
    obs
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
