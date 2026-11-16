{ packages }:
{
  a-helm-lint = {
    enable = true;
    name = "Helm lint";
    entry = "${packages.infrautils}/bin/helm lint infra/root_chart";
    files = "^infra/root_chart/.*";
    pass_filenames = false;
    language = "system";
  };

  a-helm-check = {
    enable = true;
    name = "Helm render check";
    entry = "${packages.infralint}/bin/chart-checks check-chart infra/root_chart";
    files = "^(infra/root_chart/.*|chart-checks\\.yaml)$";
    pass_filenames = false;
    language = "system";
  };
}
