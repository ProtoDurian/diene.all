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
          infralint
          infrautils
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
          age
          bun
          docker-client
          docker-compose
          git
          go-task
          infisical
          nix
          nodejs
          opentofu
          pre-commit
          shellcheck
          sops
          treefmt
          wrangler
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
