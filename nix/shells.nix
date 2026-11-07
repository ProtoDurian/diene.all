{
  pkgs,
  packages,
  env,
  shellHook,
}:
with env;
let
  shellHookWithEnvtest = shellHook + ''
    export TEST_ASSET_KUBE_APISERVER="${packages.kubernetes}/bin/kube-apiserver"
    export TEST_ASSET_ETCD="${packages.etcd}/bin/etcd"
    export TEST_ASSET_KUBECTL="${packages.kubectl}/bin/kubectl"
  '';
in
{
  cd = pkgs.mkShell {
    buildInputs = main ++ system;
    shellHook = shellHookWithEnvtest;
  };

  ci = pkgs.mkShell {
    buildInputs = lint ++ main ++ system;
    shellHook = shellHookWithEnvtest;
  };

  default = pkgs.mkShell {
    buildInputs = system ++ main ++ lint ++ dev;
    shellHook = shellHookWithEnvtest;
  };

  releaser = pkgs.mkShell {
    buildInputs = lint ++ main ++ releaser ++ system;
    shellHook = shellHookWithEnvtest;
  };
}
