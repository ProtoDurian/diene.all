{
  packages,
  formatter,
  pkgs,
  pre-commit-lib,
  env,
}:
let
  envPath = pkgs.lib.makeBinPath (env.system ++ env.main ++ env.lint ++ env.dev);
  dotnetlint-project = pkgs.buildDotnetModule {
    pname = "dotnet-base-dependencies";
    version = "0";
    src = ../.;
    projectFile = "dotnet-base.slnx";
    # Never hand-edit: regenerate with the `fetch-deps` output at the bottom of this file.
    nugetDeps = ./dotnet-deps.json;
    dotnet-sdk = packages.dotnet-sdk_10;
  };
  dotnetlint-nuget-packages = pkgs.buildEnv {
    name = "dotnetlint-nuget-packages";
    paths = dotnetlint-project.nugetDeps;
    pathsToLink = [ "/share/nuget/packages" ];
  };
  dotnetlint-empty-source = pkgs.runCommand "dotnetlint-empty-nuget-source" { } ''
    mkdir -p "$out"
  '';
  # Patch dotnetlint's /usr/bin/env shebang for pure Nix builds.
  dotnetlint-pure = pkgs.runCommand "dotnetlint-pure" { } ''
    mkdir -p "$out/bin" "$out/libexec"
    wrapper=${packages.dotnetlint}/bin/dotnetlint
    script=$(awk 'NF { line = $0 } END { print line }' "$wrapper")
    cp "$script" "$out/libexec/dotnetlint"
    patchShebangs "$out/libexec/dotnetlint"
    substitute "$wrapper" "$out/bin/dotnetlint" \
      --replace-fail "$script" "$out/libexec/dotnetlint"
    chmod +x "$out/bin/dotnetlint"
  '';
  dotnetlint-precommit = pkgs.writeShellApplication {
    name = "dotnetlint-precommit";
    runtimeInputs = [
      packages.dotnet-sdk_10
      dotnetlint-pure
    ];
    text = ''
      dotnet restore dotnet-base.slnx \
        --no-cache \
        --packages ${dotnetlint-nuget-packages}/share/nuget/packages \
        --source ${dotnetlint-empty-source} \
        -p:NuGetAudit=false \
        >/dev/null
      exec dotnetlint
    '';
  };
in
(pre-commit-lib.run {
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

    dotnetlint = {
      enable = true;
      name = ".NET lint";
      entry = "${dotnetlint-precommit}/bin/dotnetlint-precommit";
      files = "^(.*\\.cs|.*\\.csproj|Directory\\.Build\\.props|Directory\\.Packages\\.props|dotnet-base\\.slnx|global\\.json)$";
      pass_filenames = false;
      language = "system";
    };
  };
})
// {
  fetch-deps = dotnetlint-project.fetch-deps;
}
