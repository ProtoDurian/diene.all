{
  atomi,
  pkgs-2605,
  pkgs-unstable,
}:
let
  # chart-checks pin: THE ONE LINE TO CHANGE. A v5 atomipkgs release does not carry packages.chart-checks yet
  # (v5.12.0 does not), so it comes from the registry merge commit of nix-registry PR 103. Once a v5 release
  # carries it, delete this line and the chart-checks set below, and add chart-checks to the atomipkgs
  # inherit list.
  chartChecksRegistry = "github:AtomiCloud/nix-registry/2e9e31f44ca537bfcb2bba8d1586d1114b994861";
  all = rec {
    atomipkgs = (
      with atomi;
      {
        inherit
          atomiutils
          cyanprint
          dlint
          helm-schema
          infralint
          infrautils
          releaser
          skills-sync
          ;
      }
    );

    chart-checks = {
      inherit ((builtins.getFlake chartChecksRegistry).packages.${pkgs-2605.stdenv.hostPlatform.system})
        chart-checks
        ;
    };

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

    nix-unstable = (
      with pkgs-unstable;
      {
      }
    );
  };
in
with all;
atomipkgs // chart-checks // nix-2605 // nix-unstable
