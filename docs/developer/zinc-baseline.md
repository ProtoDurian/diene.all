# Zinc baseline

Zinc is the issuer set: Let's Encrypt ACME `ClusterIssuer`s that solve DNS-01 through Cloudflare. It is a pure
own-resources chart (boron-wo-workload shape). It wraps no upstream chart, runs no workload, and renders no
`Certificate`.

## What it renders

- `templates/clusterissuer.yaml`: the ONE issuer definition, instantiated once per `issuer.refs` entry. Each ref is
  `zinc-<token>` and picks a directory from `issuer.directories`.
- `templates/externalsecret.yaml`: the one ExternalSecret `zinc-secrets`. It reads the platform SecretStore with the
  folder-prefix mapping (`/shared` → `SHARED_*`, `/zinc` → `ZINC_*`). The issuers read
  `ZINC_CLOUDFLARE_API_TOKEN` from the Secret it materializes. No token is ever inlined.

## Landscape overlays (Q-I33, Q-ENV47)

| Overlay       | Refs                              | Directory                  | Zones                               |
| ------------- | --------------------------------- | -------------------------- | ----------------------------------- |
| `values.yaml` | `zinc-letsencrypt`                | staging                    | any                                 |
| `example`     | `zinc-letsencrypt`                | staging                    | any                                 |
| `pikachu`     | `zinc-letsencrypt`                | production                 | any                                 |
| `raichu`      | `zinc-letsencrypt`                | production                 | any                                 |
| `ampharos`    | `zinc-letsencrypt`                | production                 | any                                 |
| `pichu`       | `zinc-letsencrypt`                | staging (rate-limit guard) | any                                 |
| `entei`       | `zinc-staging`, `zinc-production` | staging, production        | `eevee.`/`castform.dev.atomi.cloud` |

- Lapras has no overlay: it is Boron-direct and has no public application Certificate.
- On ENTEI, automated/ephemeral CI issuance selects `zinc-staging`. Trusted interactive TLS selects `zinc-production`.
- Overlays may set only `serviceTree.landscape`, `issuer.refs` and (ENTEI) `issuer.dnsZones`. Anything else is a
  per-landscape issuer variant, and the unit tier rejects it.

## Certificate ownership

Zinc owns no `Certificate`. Registered-fleet platinum owns its serving-row infrastructure wildcard intents. On ENTEI,
the exposure materializer owns one issue-once `Certificate` per instance, with one single-label wildcard SAN per
exposed `<service>.<platform>` pair, for example `*.zinc.nitroso.kirin.eevee.dev.atomi.cloud`. A broad
`*.eevee.<host-domain>` wildcard or an exact-name-per-host intent is refused (`tests/fixtures/certificates/`).

## Cluster prerequisites

- Namespace `certs` = sulfur's release namespace. cert-manager reads ClusterIssuer secrets from its cluster resource
  namespace, so zinc must install there (`serviceTree.platform` is pinned to `certs`).
- The cert-manager CRDs (sulfur) and the ExternalSecret CRD (cobalt's ESO) must exist before install. A plain
  `helm install zinc chart --namespace certs --values chart/values.<landscape>.yaml --wait` then works in one step.
  Without the ESO CRD, the install fails at once with `no matches for kind "ExternalSecret"`; zinc has no toggle
  to skip it, since an issuer without its token Secret can never solve.
- `secret.store` defaults to `SecretStore/certs`. carbon owns the platform SecretStore and has not pinned its name;
  set `secret.store.name` once it does.

## Tests

- `task test:unit` (`scripts/ci/zinc.sh`): every mode of `scripts/validate/zinc.sh`. Each mode carries its own
  negative fixtures and checks the failure reason.
- `task test:int` (`scripts/ci/zinc-k3d.sh`): k3d, sulfur from git at its recorded `.3` SHA, the ExternalSecret CRD
  fixture, then zinc for pikachu, pichu and entei. The ClusterIssuers are read back from the API. The cert-manager
  controller is scaled to 0, so nothing contacts Let's Encrypt; the webhook still validates every object.
- The rendered-manifest stage runs `kubeconform -strict` against `tests/schemas/` (from the pinned CRDs). VAP
  evaluation is vacuous: zinc renders no workload or Service.

## Tokenization surface

Chart name `zinc`, release namespace `certs`, the k3d cluster/registry names, the package name in `publish.sh`, the
schema title and the six Taskfile landscape includes.
