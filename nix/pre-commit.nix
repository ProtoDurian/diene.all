{
  packages,
  formatter,
  pkgs,
  pre-commit-lib,
  env,
}:
let
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
