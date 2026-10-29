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
    # ### bun-base-main
    # #### source: bun-base
    bun
    nodejs
    # setup.sh runs `releaser conventions`; the probes run setup in .#ci
    releaser
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
