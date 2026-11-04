{
  atomi,
  pkgs-2605,
  pkgs-unstable,
}:
let
  all = rec {
    atomipkgs = (
      with atomi;
      {
        inherit
          atomiutils
          cyanprint
          dlint
          go
          # Axis-pure slices: the infralint/infrautils aggregates ship helm, helm-docs and helmlint.
          infralint-core
          infralint-docker
          infrautils-core
          infrautils-docker
          releaser
          skills-sync
          ;
      }
    );

    nix-2605 = (
      with pkgs-2605;
      {
        inherit
          actionlint
          git
          go-task
          go-tools
          gofumpt
          golangci-lint
          gotestsum
          gotools
          govulncheck
          infisical
          nix
          pre-commit
          shellcheck
          treefmt
          ;
      }
    );

    nix-unstable = (
      with pkgs-unstable;
      {
      }
    );
  };
in
with all;
atomipkgs // nix-2605 // nix-unstable
