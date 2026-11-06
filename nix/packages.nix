{
  atomi,
  atomiLib,
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
          bun
          dpkg
          gh
          git
          go
          go-task
          goreleaser
          infisical
          nix
          nodejs
          pre-commit
          ripgrep
          rpm
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

    cli =
      let
        manifest = builtins.fromJSON (builtins.readFile ../package.json);
        cliNames = builtins.attrNames manifest.bin;
        cliName =
          if builtins.length cliNames == 1 then
            builtins.head cliNames
          else
            builtins.throw "bun-cli package requires exactly one package.json bin entry";
        entry = manifest.bin.${cliName};
        src = pkgs-2605.lib.cleanSourceWith {
          src = ../.;
          filter =
            path: _type:
            let
              base = baseNameOf path;
            in
            !(builtins.elem base [
              "node_modules"
              "dist"
              "prebuilt"
              "coverage"
              ".direnv"
              "result"
            ]);
        };
      in
      {
        # Keep the pinned bun; the compiled runtime and depsHash depend on it.
        bun-cli = atomiLib.buildBunCli {
          name = cliName;
          version = manifest.version;
          inherit src;
          entrypoint = entry;
          depsHash = "sha256-mIb7xR1Cq1bjxDU0qK7T3jC5K0R1GfDiJy5LODpDfDg=";
          bun = pkgs-2605.bun;
        };
      };
  };
in
with all;
atomipkgs // nix-2605 // nix-unstable // cli
