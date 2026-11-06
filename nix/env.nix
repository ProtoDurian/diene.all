{ pkgs, packages }:
with packages;
{
  dev = [
    docker-client
    docker-compose
    git
    go-task
    goreleaser
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
    age
    bun
    cyanprint
    git
    go-task
    infisical
    nodejs
    opentofu
    releaser
    shellcheck
    sops
    wrangler
  ];

  releaser = [
    goreleaser
    releaser
  ];

  system = [
    atomiutils
    infrautils
    nix
  ];
}
