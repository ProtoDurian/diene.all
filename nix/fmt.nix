{ treefmt-nix, pkgs, ... }:
let
  fmt = {
    projectRootFile = "flake.nix";

    # enable or disable formatters, see https://github.com/numtide/treefmt-nix#supported-programs
    programs = {
      actionlint.enable = true;
      nixfmt.enable = true;
      prettier = {
        enable = true;
        excludes = [
          ".claude/skills/vendor/**"
          "Changelog.md"
          "docs/developer/CommitConventions.md"
          "infra/root_chart/**"
          "*.ts"
          "*.tsx"
          "*.mts"
          "*.cts"
          "*.js"
          "*.jsx"
          "*.mjs"
          "*.cjs"
          "*.json"
          "*.jsonc"
        ];
      };
      shfmt.enable = true;
    };

    settings.formatter.biome = {
      command = "./scripts/local/biome-format.sh";
      includes = [
        "*.ts"
        "*.tsx"
        "*.mts"
        "*.cts"
        "*.js"
        "*.jsx"
        "*.mjs"
        "*.cjs"
        "*.json"
        "*.jsonc"
      ];
    };

  };
in
(treefmt-nix.lib.evalModule pkgs fmt).config.build.wrapper
