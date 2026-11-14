{
  pkgs,
  packages,
  env,
  shellHook,
}:
with env;
{
  # CI shells install no git hooks: nothing commits in CI.
  cd = pkgs.mkShell {
    buildInputs = main ++ system;
  };

  ci = pkgs.mkShell {
    buildInputs = lint ++ main ++ system;
  };

  default = pkgs.mkShell {
    buildInputs = system ++ main ++ lint ++ dev;
    inherit shellHook;
  };

  releaser = pkgs.mkShell {
    buildInputs = lint ++ main ++ releaser ++ system;
    inherit shellHook;
  };
}
