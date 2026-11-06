# xenon

![Version: 0.1.0](https://img.shields.io/badge/Version-0.1.0-informational?style=flat-square) ![Type: application](https://img.shields.io/badge/Type-application-informational?style=flat-square) ![AppVersion: 0.9.0](https://img.shields.io/badge/AppVersion-0.9.0-informational?style=flat-square)

AtomiCloud Resource Metrics API - conditional passthrough of kubernetes-sigs/metrics-server, ON only where no built-in provider exists

## Needed/provided matrix

Xenon provides the Resource Metrics API (`v1beta1.metrics.k8s.io`) for HPA and `kubectl top`. It is needed only where
the cluster has no built-in provider. Each overlay declares that fact as `builtInMetricsProvider`; the chart refuses an
overlay whose `upstream.enabled` is not its opposite. OFF renders nothing, so the chart installs everywhere. ON needs
Kubernetes 1.34+ (metrics-server 0.9). `toggle-map.yaml` is the machine-readable form of this table.

| Landscape | Substrate | Built-in provider | Xenon | Kubelet TLS |
| --- | --- | --- | --- | --- |
| primordial | central cluster | no (none declared) | ON | secure |
| lapras | local k3d/k3s | yes (k3s bundles metrics-server) | OFF | bundled |
| ditto | fresh k3d, or the nsc built-in k3s in CI | yes (k3s bundles metrics-server) | OFF | bundled |
| rotom | retained offline k3d/k3s | yes (k3s bundles metrics-server) | OFF | bundled |
| absol | fresh offline k3d, or the nsc built-in k3s in CI | yes (k3s bundles metrics-server) | OFF | bundled |
| eevee | hosted workload vcluster | no (no bundled provider) | ON | `--kubelet-insecure-tls` |
| castform | preview workload vcluster | no (no bundled provider) | ON | `--kubelet-insecure-tls` |
| serving | per registered serving cluster | per cluster | per cluster | secure |

Serving is evaluated per registered cluster. Each cluster's overlay restates `builtInMetricsProvider`; a cluster whose
substrate bundles a provider must set it `true` and xenon OFF.

| Serving substrate | Built-in provider | Xenon |
| --- | --- | --- |
| EKS classic | no (not preinstalled) | ON |
| EKS Auto | no (not managed; the community add-on is a separate install) | ON |
| DOKS | no (metrics-server is a user-managed Marketplace install) | ON |
| on-prem | no (not preinstalled) | ON |

## Requirements

| Repository | Name | Version |
|------------|------|---------|
| https://kubernetes-sigs.github.io/metrics-server | upstream(metrics-server) | 3.14.0 |

## Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| builtInMetricsProvider | bool | `false` | The declared fact the toggle derives from: true when the cluster already serves `v1beta1.metrics.k8s.io` (k3s bundles metrics-server). Then `upstream.enabled` must be false; otherwise it must be true. |
| labelPrefix | string | `"atomi.cloud"` | Prefix used by every service-tree label. |
| serviceTree | object | `{"layer":"1","module":"metrics","platform":"metrics","service":"xenon"}` | Stable four-slot service-tree projection. Landscape and cluster are added by independent overlays. |
| upstream | object | `{"commonLabels":{"atomi.cloud/layer":"1","atomi.cloud/module":"metrics","atomi.cloud/platform":"metrics","atomi.cloud/service":"xenon"},"deploymentAnnotations":{"reloader.stakater.com/auto":"true"},"enabled":true,"fullnameOverride":"xenon-metrics","nameOverride":"metrics-server","podLabels":{"atomi.cloud/layer":"1","atomi.cloud/module":"metrics","atomi.cloud/platform":"metrics","atomi.cloud/service":"xenon"},"podSecurityContext":{"runAsNonRoot":true},"resources":{"limits":{"cpu":"500m","memory":"400Mi"},"requests":{"cpu":"100m","memory":"200Mi"}}}` | metrics-server 3.14.0 (app 0.9.0, Kubernetes 1.34+) values: upstream defaults plus the toggle, LPSM labels, Reloader, pod non-root and limits. No ServiceMonitor, no metrics endpoint (upstream defaults stay off). |
| upstream.enabled | bool | `true` | The xenon toggle (Helm dependency condition). ON exactly when `builtInMetricsProvider` is false. |
| upstream.fullnameOverride | string | `"xenon-metrics"` | Conforming `<service>-<token>` name for every upstream object. |
| upstream.nameOverride | string | `"metrics-server"` | Standard `app.kubernetes.io/name` (and selector) value; the `upstream` alias would leak in otherwise. |
