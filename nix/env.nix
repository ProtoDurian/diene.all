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
    dn-inspect
    dotnetlint
    infralint
    pre-commit
    shellcheck
    skills-sync
    treefmt
  ];

  main = [
    cyanprint
    dotnet-sdk_10
    git
    go-task
    infisical
    releaser
    shellcheck
    xmlstarlet
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
