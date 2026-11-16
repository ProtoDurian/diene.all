{
  pkgs,
  packages,
  env,
  shellHook,
}:
with env;
{
  cd = pkgs.mkShell {
    buildInputs = main ++ system;
  };

  ci = pkgs.mkShell {
    buildInputs = lint ++ main ++ system ++ ci;
  };

  default = pkgs.mkShell {
    buildInputs = system ++ main ++ lint ++ dev;
    inherit shellHook;
  };

  precommit = pkgs.mkShell {
    buildInputs = lint ++ main ++ system;
    inherit shellHook;
  };

  releaser = pkgs.mkShell {
    buildInputs = lint ++ main ++ releaser ++ system;
  };
}
