# Helm wrapper baseline

This branch is the reusable platform-chart wrapper shape. It vendors a pinned upstream dependency, but wrapper-owned templates carry the contracts that every concrete platform chart must preserve.

## Rendering model

Render values in two independent dimensions:

1. `chart/values.yaml` — platform/service/module/layer defaults.
2. `chart/values.<landscape>.yaml` — landscape identity and landscape behavior.
3. `chart/values.<cluster>.yaml` — normally-thin cluster identity or genuine cluster overrides.

The sample stack is `values.yaml` → `values.example.yaml` → `values.lapras.yaml`. Landscape and cluster vocabularies must remain disjoint. Do not create cross-product filenames.

Run `task build` or `task example:lapras:template`. `debug` and `template` render from the committed `chart/charts/` and need no network; `install` runs `helm dependency build` first and works against any kube context. There is no local cluster: install is proven on Garden lapras, never in this template.

## Default shape

`upstream.enabled` is `true` (podinfo is the stand-in upstream), so a plain `values.yaml` render holds only the upstream objects. Everything wrapper-owned is off:

- `workload.enabled` (the wrapper Deployment, Service and config ConfigMap) is one switch, default `false`;
- `migration`, `secret`, `gateway`, `webhookRoute` and `primordial` default `false`, and so do the four primordial sub-switches (`virtualLandscapeService`, `logtoApp`, `problem`, `cloudflareDeploy`).

Template probes switch everything on with `probes/fixtures/values.all-on.yaml`, stacked on the committed values. The upstream chart cannot read `labelPrefix`, so the `upstream:` block carries the platform annotations under the default prefix, with values taken from `serviceTree` through YAML anchors (landscape and cluster come from the overlays).

## Identity and naming

- `labelPrefix` is the only prefix input. Every service-tree label and annotation helper reads it.
- LPSM remains `{landscape, platform, service, module}`. The platform hostname slot always comes from the release namespace; a values file cannot stamp another platform.
- Ordinary hostnames are `<module>.<service>.<namespace>.<landscape>.<zone>`.
- Optional physical-instance hostnames are `<module>.<service>.<namespace>.<instance>.<landscape>.<zone>`. Instance is returned separately by the parser and never becomes an LPSM slot.
- Every hostname label, generated or parsed, must be one lowercase DNS-1123 label of at most 63 bytes. The parser refuses empty segments.
- `instance` is opaque: the helper accepts only one lowercase DNS-1123 label of at most 63 bytes and refuses dots, uppercase, an explicit empty string and longer values. An absent instance gives the ordinary form.
- The fleet identity endpoint is `api.lithium.aldehyde.<landscape>.cluster.atomi.cloud` for a concrete landscape. The `identityIssuer` helper accepts only a landscape listed in `primordial.identity.concreteLandscapes`. It refuses anything else, and it names the consumer platform (release namespace) and `primordial.vlandscape` explicitly.
- Physical ids are repository-qualified before normalization. DNS-1123 labels longer than 63 characters are shortened with a stable hash, while original and normalized values are stored together as annotations.
- Resource names use `<service>-<token>` with exactly one dash. Tokens fuse components (`main-cache` → `maincache`). The primary workload token is `serviceTree.module`, so `fullnameOverride` must equal `<service>-<module>`. Every enabled dependency receives an explicit conforming `fullnameOverride`; the `fullname` check renders the sub-chart and also covers generated Secret names.

The helpers are generic by design. Final environment-owned instance segments, hosted profile fixtures, and exposure semantics stay outside this node until their owning work lands.

## Secrets and config

The wrapper assumes the platform SecretStore already exists. It emits one service-scoped ExternalSecret, targets one Secret named `<service>-secrets`, and uses folder-level `dataFrom.find` plus rewrite rules. The key prefix comes from the folder: strip the leading `/`, uppercase it and turn every non-alphanumeric character into `_`.

- `/shared/X` → `SHARED_X`
- `/wrapper/X` → `WRAPPER_X`
- `/team/wrapper-api/X` → `TEAM_WRAPPER_API_X`

Rendering refuses when one prefix equals or starts with the other, or a folder yields an empty prefix.

Individual key mappings are forbidden. There is no secret-provider toggle.

Application config lives in root `config/*.yaml`. `scripts/local/vendor-chart-config.sh` copies it into ignored `chart/files/config/` immediately before chart build/render; `.Files.Glob` bundles those files into the ConfigMap. Generated copies are never committed.

## Workloads and migration

Reloader's annotation is emitted by default for every wrapper-owned workload. A workload can explicitly set its own `reloader.enabled: false` when automatic restart is unsafe.

The migration Job is a separate object with:

- `helm.sh/hook: pre-install,pre-upgrade`
- `argocd.argoproj.io/hook: PreSync`
- `helm.sh/hook-delete-policy: before-hook-creation`

The Deployment always uses `RollingUpdate`; the hook never recreates it.

## Chart checks

A chart instance keeps exactly three chart-check pre-commit hooks. CI's existing `precommit` job runs them, and restores `.chart-checks/` from `actions/cache` keyed on `hashFiles('chart-checks.yaml')` first.

- `a-wrapper-helm-lint` — `helm lint` and `helm template` on the three committed stacks (`values.yaml`; `+ values.example.yaml`; `+ values.example.yaml + values.lapras.yaml`). `helm lint` also validates each stack against `values.schema.json`.
- `a-wrapper-values-schema` — a generator: it regenerates `chart/values.schema.json` in place with `scripts/local/generate-chart-schema.sh`, so a stale schema makes pre-commit fail.
- `a-wrapper-manifests` — renders the same three stacks and runs `chart-checks check` on them: `kubectl-validate` against the Kubernetes schemas plus the installed CRDs, then `kyverno apply` with the installed vanadium VAP definitions. No kind pre-filter and no object is dropped: each VAP's `matchConstraints` selects.

`a-wrapper-helm-docs` stays as it is: it generates `chart/README.md` and is not a check. `scripts/validate/helm-wrapper.sh` ships only the modes these hooks call (`lint`, `schema`, `manifests`). Every other check of this template (labels, Reloader, secret, fullname, primordial, LPSM, LB, task surface, publish modes, version and release lint) runs from `probes/checks/` only, which is chain-side and never materialized. The contracts ConfigMap (LPSM and instance vectors) lives in the probe fixture chart `probes/fixtures/contracts-chart/`, which takes `chart/` as a `file://` dependency so its template renders the shipped helpers.

`chart-checks.yaml` at the repo root is the pinned list (`kubernetes: "1.30"`, every `sha256` and `commit` quoted): the vanadium policy chart, the dependency-operator and logto-operator CRDs, the ExternalSecret CRDs and the Gateway API CRDs. `chart-checks install` (run by `scripts/local/setup.sh`) fetches them into the gitignored `.chart-checks/`; `chart-checks check` reads only that folder. Until vanadium and the two operators publish, those three entries point at today's copies at pinned `diene.all` commits and carry `temporary: true` with a reason; the LogtoApp entry is a JSON-schema entry because no LogtoApp CRD exists yet. Instances add their own entries to their own `chart-checks.yaml`.

The tool comes from `atomipkgs` (`packages.chart-checks`); `kubectl-validate` and `kyverno` arrive inside its closure. Until a v5 release carries it, `nix/packages.nix` takes it from the registry merge commit named on the `chartChecksRegistry` line: that one line is the pin to change.

The platform conventions (labels, the Reloader annotation unless opted out, `<service>-<token>` names, the ExternalSecret folder-prefix shape) are vanadium rules. The wiring probe carries one sabotage (an upstream image tagged `latest`); per-rule proof lives in vanadium.

## Primordial helpers

The sample renders the frozen current shapes for `PlatformDependency`, `VirtualLandscapeService`, `LogtoApp`, `Problem`, and `CloudflareDeploy`:

- dependency delivery is exactly `external | local | replicated`;
- a v-landscape target has one writer plus `placement.preferredHost` and no sharing fields;
- VLS carries no free-form hostname;
- LogtoApp renders one CR per `primordial.logtoApp.landscapes` entry, each with `identityRef: {platform, landscape}`; the issuer and the credential destination (`<landscape>:/<service>`) are recorded as annotations because T3 derives them and defines no spec field for them; a repeated or name-colliding landscape, the consumer platform, the v-landscape or any landscape not in `primordial.identity.concreteLandscapes` refuses;
- LogtoApp declares paths, `extraRedirectUris`, and `resourceRefs`, never per-row redirects;
- Problem is `atomi.cloud/v1alpha1` and the other kinds `fleet.atomi.cloud/v1alpha1` (the installed CRDs decide; `primordial.apiVersions` holds them);
- Problem carries `spec.module` and fuses the module into its name;
- CloudflareDeploy uses `desiredVersionFrom.tag`, never a hand-pinned version id.

These are helper contracts, not CRD ownership. The T3/operator nodes own final API groups, controllers, and installed CRDs.

## Gateway and webhook conventions

The gateway Service is always `type: LoadBalancer`:

- AWS: deterministic subnet list paired positionally with NLB Elastic IP allocation ids. This path carries the standing EKS Auto Mode compatibility assumption until the user completes the live test.
- OCI: reserved public IP annotation.
- DigitalOcean: provider-lifetime-stable load balancer IP, with no fixed-IP annotation.

NodePort and hostPort are absent. TLS terminates at the gateway platform, not this Service.

Every gateway exposes the health path `contracts.health.path` (`/healthz`) and must return a 2xx response. Webhook receivers use `/internal/webhooks/{provider}`. Mercury probes every candidate: exactly one `200` (the owner) and `421` from every other candidate (a non-owner disclaiming, nothing else). Any other response is a real delivery failure. The probe fixture chart's contracts ConfigMap records this as `webhook.owner`, `webhook.nonOwner` and `webhook.other`. The checked-in HTTPRoute is a scaffold only; product handlers implement the protocol.

## Publishing

OCI is the default publish/consume mode. Git chart repositories remain secondary. The only exception classes are the moving-tag fleet compiler and boot-time Primordial/seed charts; the exact bootstrap roster remains intentionally held for its owner.

`scripts/release/bump.sh` stamps `chart/Chart.yaml` at the release commit. `scripts/ci/publish.sh` refuses a manifest/tag mismatch, regenerates Helm docs, and supports git packaging plus OCI dry-run or push. It registers every `https://` dependency repository from `chart/Chart.yaml` in a throwaway Helm repository config before `helm dependency build`, so a fresh CD runner needs no `helm repo add`. No external publish is needed for local proof.

## Tokenization surface

Tokenize these isolated scalars when materializing an instance:

- chart and release name (`<service>-<token>`, exactly one dash);
- serviceTree platform/service/module/layer values;
- `labelPrefix`;
- upstream chart name/version/repository;
- vendored tgz filename;
- skopeo image refs used by `latest`;
- OCI/ghcr organization path;
- git repository URL (the secondary git-as-chart-repo mode);
- landscape overlay filenames (`values.<landscape>.yaml`);
- cluster overlay filenames (`values.<cluster>.yaml`);
- `chart-checks.yaml` entries;
- repository-qualified physical instance id;
- normalized instance DNS label;
- original-instance metadata annotation;
- hostname zone selection.

Held ENV profile names, final parser fixtures, frontend exposure rules, hosted substrate behavior, final bootstrap enumeration and the CR API versions (their owning operators freeze them) are not tokenized here because this node does not own those decisions.
