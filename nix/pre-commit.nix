{
  packages,
  formatter,
  pkgs,
  pre-commit-lib,
  env,
}:
let
  # Every tool the dev shell provides, for hooks that look tools up by name on PATH (e.g. dlint toolchain-smoke inside the nix flake check sandbox).
  envPath = pkgs.lib.makeBinPath (env.system ++ env.main ++ env.lint ++ env.dev);
in
pre-commit-lib.run {
  src = ../.;

  # hooks
  hooks = {
    # formatter
    treefmt = {
      enable = true;
      package = formatter;
      excludes = [
      ];
    };
  };
}
