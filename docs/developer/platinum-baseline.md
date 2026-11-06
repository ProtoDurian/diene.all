# Platinum baseline

Platinum (graph node `charts/kgateway`) is the fleet's Gateway API ingress chart. It is a materialized
chart product: it inherits the helm-wrapper shape (stacked values, generated schema, the
rendered-manifest validation stage, `<service>-<token>` names, LPSM labels, dual publish modes) but
carries no probe matrix. Evidence is a testing pyramid with negative fixtures as ordinary tests.

## What it wraps

`chart/charts/` vendors two pinned upstreams from `oci://cr.kgateway.dev/kgateway-dev/charts`:

- `kgateway` v2.5.0 (alias `upstream`, on by default) — the control plane, named `platinum-gateway`
  (the primary workload). Images: `cr.kgateway.dev/kgateway-dev/kgateway:v2.5.0` and the generated
  proxy `cr.kgateway.dev/kgateway-dev/envoy-wrapper:v2.5.0`.
- `kgateway-crds` v2.5.0 (alias `crds`, off by default) — the `gateway.kgateway.dev` CRDs.

Install order per cluster: Gateway API v1.7.0 standard CRDs, then `kgateway-crds` as its own release,
then platinum. The release cannot carry its own CRDs because it renders `GatewayParameters` and
`DirectResponse` objects. kgateway v2.5.0 needs Kubernetes 1.33 or newer.

## Rendering model

Two independent stacked dimensions: `values.yaml` → landscape overlay → cluster overlay.

- Serving landscapes: `values.pichu.yaml`, `values.pikachu.yaml`, `values.raichu.yaml`, `values.ampharos.yaml`.
- Cluster overlays carry the provider settings. Live marks are fleet deployment input; the
  representative overlays are `values.opal.yaml` (DigitalOcean), `values.ruby.yaml` (AWS) and
  `values.emerald.yaml` (OCI).
- Loopback-only local landscapes: `values.ditto.yaml`, `values.rotom.yaml`, `values.absol.yaml`
  (`provider: local`, no cloud annotation, no registered-fleet Certificate).
- Lapras is Boron-direct and has no platinum overlay.
- ENTEI: provider cluster overlay, then `values.entei.yaml`.

Every overlay that changes `serviceTree` also sets the same key in `upstream.commonLabels`; render
refuses when the kgateway labels differ from the LPSM set.

## Objects

| Object                     | Name                                          | Notes                                                |
| -------------------------- | --------------------------------------------- | ---------------------------------------------------- |
| GatewayClass               | `platinum`                                    | controller `kgateway.dev/kgateway`                   |
| Gateway                    | `platinum-shared`                             | the one shared Gateway per cluster                   |
| GatewayParameters          | `platinum-proxy`                              | keeps kgateway's generated proxy Service `ClusterIP` |
| Service                    | `platinum-edge`                               | `type: LoadBalancer`, the only public origin         |
| HTTPRoute + DirectResponse | `platinum-healthz`                            | `Exact /healthz` answered `200` by the proxy         |
| Certificate ×2             | `platinum-certprimary`, `platinum-certbackup` | registered fleet only                                |

`platinum-proxy` also gives the generated envoy pods CPU/memory requests and limits and pod
`runAsNonRoot`, so the fleet VAP admits them. kgateway's default `kgateway` GatewayClass points at it
too (`upstream.gatewayClassParametersRefs`), so no Gateway gets a second LoadBalancer.

`platinum-edge` selects the proxy by `gateway.networking.k8s.io/gateway-name: platinum-shared`.
The proxy listens on the listener ports themselves (80/443); the k3d tier checks the edge
targetPorts against kgateway's generated proxy Service.

## Fixed-IP LoadBalancer annotations

The cloud LB is the sole public origin; NodePort and hostPort never appear. A NodePort Service is
denied by the inherited VAP stage (platinum's one wiring sabotage).

- AWS NLB: subnet list paired with fleet-allocated Elastic IP allocations.
- OCI: NLB on a reserved public IP.
- DigitalOcean: no reserved IP for LBs; the named LB keeps its IP for its lifetime only. On
  recreation the traffic controller re-derives A-sets from `ClusterRegistration.status`.

## Health endpoint

`/healthz` on the `http` listener is the target of the traffic controller's 5s poll (once per cluster
per tick). Chart scope is "route rendered + 2xx in k3d"; the poll itself belongs to T3.

## Certificates and issuers

Platinum renders no issuer. Registered-fleet stacks render the primary `*.cluster.atomi.cloud`
wildcard and the Route53 backup-domain wildcard against zinc's `zinc-letsencrypt` ClusterIssuer,
each served by a terminating HTTPS listener. The backup domain value is a placeholder until the backup
domain is named.

## ENTEI dev-host overlay

ENTEI is a registered, infrastructure-only, `traffic=false` host. With `devHost.enabled` platinum
renders only the shared GatewayClass, Gateway, LoadBalancer and the health route: no Certificate, no
ListenerSet, no per-host HTTPRoute. The exposure materializer owns the issue-once instance
Certificate (one single-label wildcard per service/platform pair) and the per-host `ListenerSet`
(`gateway.networking.k8s.io/v1`, Gateway API v1.7.0 standard) and `HTTPRoute`.

The Gateway admits ListenerSets only from namespaces labelled `atomi.cloud/managed-vcluster: "true"`.

Direct mutation of the shared Gateway is disabled by default. `devHost.emergencyListeners` is an
emergency-only fallback: its listeners are appended to the shared Gateway and inherit the Gateway
listener ceiling (64 listeners, render refuses beyond it) that ListenerSet avoids.

## Tests

- Unit (`scripts/ci/platinum.sh`): schema, lint and render over every stack, LPSM labels, fullnames, gateway,
  health, LB, ENTEI, issuer-free, pins, reloader opt-out, rendered-manifest VAP stage, publish modes.
- Both k3d tiers bind the parent VAP (`Deny`) first, check the GatewayClass set and the default class,
  and show the VAP denying a proxy without envoy resources.
- Integration (`scripts/ci/platinum-k3d.sh`, ditto stack): Gateway Programmed, sample HTTPRoute,
  `/healthz` 2xx through `platinum-edge`, local OCI round-trip.
- ENTEI fixtures (`scripts/ci/platinum-entei.sh`): cert-manager from `tests/fixtures/entei/`, a fixture
  CA Issuer and instance Certificate, a ClusterIP Service, ListenerSet and HTTPRoute; exact-host TLS,
  Service replacement, named-port change, then deletion leaves the Gateway and Certificate unchanged.
