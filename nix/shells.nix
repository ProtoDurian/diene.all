{
  pkgs,
  packages,
  env,
  shellHook,
  preCommitConfig,
}:
with env;
{
  # CI shells install no git hooks: nothing commits in CI. The ci shell hands the
  # generated hook config in PRE_COMMIT_CONFIG_FILE (scripts/local/pre-commit-run.sh).
  cd = pkgs.mkShell {
    buildInputs = main ++ system;
  };

  ci = pkgs.mkShell {
    buildInputs = lint ++ main ++ system;
    PRE_COMMIT_CONFIG_FILE = preCommitConfig;
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
