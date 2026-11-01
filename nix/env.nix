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
    # ### dotnet-base-lint
    # #### source: dotnet-base
    dn-inspect
    dotnetlint
  ];

  main = [
    # ### dotnet-base-main
    # #### source: dotnet-base
    dotnet-sdk_10
    xmlstarlet
    cyanprint
    git
    go-task
    infisical
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
