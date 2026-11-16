{ packages }:
{
  a-helm-check = {
    enable = true;
    name = "Helm render check";
    entry = "${packages.infralint}/bin/chart-checks check-chart infra/root_chart";
    files = "^(infra/root_chart/.*|chart-checks\\.yaml)$";
    pass_filenames = false;
    language = "system";
  };
}
