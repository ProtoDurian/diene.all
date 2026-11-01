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
    nix-unstable = (with pkgs-unstable; { });
    nix-2605 = (
      with pkgs-2605;
      {
        inherit
          actionlint
          git
          go-task
          infisical
          nix
          pre-commit
          shellcheck
          treefmt
          ;
      }
    );
    # ### dotnet-base-packages
    # #### source: dotnet-base
    # dotnetlint and dn-inspect analyse with the repository SDK, not their own.
    dotnet-base = {
      dotnetlint = atomi.dotnetlint.override { dotnetPackage = pkgs-2605.dotnet-sdk_10; };
      dn-inspect = atomi.dn-inspect.override { dotnetPackage = pkgs-2605.dotnet-sdk_10; };
      inherit (pkgs-2605) dotnet-sdk_10 xmlstarlet;
    };
  };
in
with all;
nix-2605 // nix-unstable // atomipkgs // dotnet-base
