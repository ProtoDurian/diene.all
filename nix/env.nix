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
    dn-inspect
    dotnetlint
    infralint-core
    infralint-docker
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
    infrautils-core
    infrautils-docker
    nix
  ];
}
