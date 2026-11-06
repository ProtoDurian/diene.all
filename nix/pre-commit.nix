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
        "^\\.claude/skills/vendor/"
        "^Changelog\\.md$"
        "^docs/developer/CommitConventions\\.md$"
        "^infra/root_chart/"
      ];
    };

    a-dlint = {
      enable = true;
      name = "dlint";
      entry = "${packages.atomiutils}/bin/bash -c 'PATH=${envPath}:\$PATH ${packages.dlint}/bin/dlint lint'";
      pass_filenames = false;
      language = "system";
    };

    a-helm-lint = {
      enable = true;
      name = "Helm lint";
      entry = "${packages.infrautils}/bin/helm lint infra/root_chart";
      files = "^infra/root_chart/.*";
      pass_filenames = false;
      language = "system";
    };

    a-infisical = {
      enable = true;
      name = "Secrets scan";
      entry = "${packages.infisical}/bin/infisical scan . -v --redact";
      pass_filenames = false;
      language = "system";
    };

    a-infisical-staged = {
      enable = true;
      name = "Staged secrets scan";
      entry = "${packages.infisical}/bin/infisical scan git-changes --staged -v --redact";
      pass_filenames = false;
      language = "system";
    };

    a-markdownlint = {
      enable = true;
      name = "Markdown lint";
      entry = "${pkgs.markdownlint-cli2}/bin/markdownlint-cli2";
      files = "^(docs/standards/.*\\.md|\\.claude/skills/[^/]+/SKILL\\.md)$";
      pass_filenames = true;
      language = "system";
    };

    a-releaser-commit = {
      enable = true;
      name = "Conventional commit";
      entry = "${packages.releaser}/bin/releaser lint-commit -c release.yaml";
      stages = [ "commit-msg" ];
      pass_filenames = true;
      language = "system";
    };

    a-skills-sync = {
      enable = true;
      name = "Vendored skills";
      entry = "${packages.skills-sync}/bin/skills-sync sync --frozen";
      pass_filenames = false;
      language = "system";
    };

    a-shellcheck = {
      enable = true;
      name = "Shellcheck";
      entry = "${packages.shellcheck}/bin/shellcheck -x --source-path=SCRIPTDIR";
      files = ".*\\.sh$";
      pass_filenames = true;
      language = "system";
    };

    a-deadcode = {
      enable = true;
      name = "Go dead code";
      entry = "${packages.atomiutils}/bin/bash -c 'PATH=${envPath}:\$PATH CGO_ENABLED=0 ./scripts/local/deadcode-strict.sh'";
      files = "(^|/).*\\.go$|^go\\.(mod|sum)$";
      pass_filenames = false;
      language = "system";
    };

    a-golangci-lint = {
      enable = true;
      name = "golangci-lint";
      entry = "${packages.atomiutils}/bin/bash -c 'PATH=${envPath}:\$PATH CGO_ENABLED=0 ${packages.golangci-lint}/bin/golangci-lint run --timeout 5m ./...'";
      files = "(^|/).*\\.go$|^go\\.(mod|sum)$|^\\.golangci\\.yaml$";
      pass_filenames = false;
      language = "system";
    };

    a-operator-markers = {
      enable = true;
      name = "Operator marker lint";
      entry = "${packages.atomiutils}/bin/bash -c 'PATH=${envPath}:\$PATH CGO_ENABLED=0 ./scripts/validate/operator-markers.sh'";
      files = "^(api/|adapters/operator/controllers/).*\\.go$|^scripts/validate/operator-markers\\.sh$";
      pass_filenames = false;
      language = "system";
    };

    a-operator-architecture = {
      enable = true;
      name = "Operator architecture boundary";
      entry = "${packages.atomiutils}/bin/bash -c 'PATH=${envPath}:\$PATH CGO_ENABLED=0 ./scripts/validate/operator-architecture.sh'";
      files = "^(lib/operator/|adapters/operator/controllers/|tools/archcheck/).*\\.go$|^scripts/validate/operator-architecture\\.sh$";
      pass_filenames = false;
      language = "system";
    };

    a-operator-rbac = {
      enable = true;
      name = "Operator RBAC minimality";
      entry = "${packages.atomiutils}/bin/bash -c 'PATH=${envPath}:\$PATH CGO_ENABLED=0 ./scripts/validate/operator-rbac.sh'";
      files = "^(adapters/operator/controllers/.*\\.go|infra/root_chart/templates/rbac/.*|scripts/validate/operator-rbac\\.sh)$";
      pass_filenames = false;
      language = "system";
    };

    a-operator-crd-drift = {
      enable = true;
      name = "Operator CRD drift";
      entry = "${packages.atomiutils}/bin/bash -c 'PATH=${envPath}:\$PATH CGO_ENABLED=0 ./scripts/validate/operator-crd-drift.sh'";
      files = "^(api/.*\\.go|infra/root_chart/templates/crds/.*|scripts/validate/operator-crd-drift\\.sh)$";
      pass_filenames = false;
      language = "system";
    };
  };
}
