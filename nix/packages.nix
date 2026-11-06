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
        inherit
          goreleaser
          ;
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
            builtins.throw "aseity requires exactly one package.json bin entry";
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
              ".wrangler"
              "result"
            ]);
        };
      in
      {
        # Keep the pinned bun; the compiled runtime and depsHash depend on it.
        aseity = atomiLib.buildBunCli {
          name = cliName;
          version = manifest.version;
          inherit src;
          entrypoint = entry;
          depsHash = "sha256-rUm8WlPGQxXUV+H8VeiZDn7hnZjrx18+nn3M+/hkZnU=";
          bun = pkgs-2605.bun;
        };
      };
  };
in
with all;
atomipkgs // nix-2605 // nix-unstable // cli
