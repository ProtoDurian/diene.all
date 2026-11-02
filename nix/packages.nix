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
          dotnet-sdk_10
          git
          go-task
          infisical
          nix
          pre-commit
          shellcheck
          treefmt
          xmlstarlet
          ;
      }
    );

    nix-unstable = (
      with pkgs-unstable;
      {
      }
    );

    # dotnetlint and dn-inspect analyse with the repository SDK, not their own.
    dotnet-base = {
      dotnetlint = atomi.dotnetlint.override { dotnetPackage = pkgs-2605.dotnet-sdk_10; };
      dn-inspect = atomi.dn-inspect.override { dotnetPackage = pkgs-2605.dotnet-sdk_10; };
    };
  };
in
with all;
atomipkgs // nix-2605 // nix-unstable // dotnet-base
