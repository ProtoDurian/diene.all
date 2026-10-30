{
  packages,
  formatter,
  pkgs,
  pre-commit-lib,
  env,
}:
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
