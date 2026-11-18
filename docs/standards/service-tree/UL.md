# service-tree

durian.cloud > engineering > standards > service-tree

The naming scheme that places every product resource in one tree

| Word | Means | Also called | See |
|---|---|---|---|
| cluster | A Kubernetes cluster inside one landscape, unique within it; named with gemstones. |  | [landscape](#landscape) |
| landscape | The deployment environment, by purpose, region and segment; named with Pokemon, such as pichu, pikachu and raichu. |  | [service tree](#service-tree-1), [cluster](#cluster) |
| module | An actual component of a service, such as databases, an API or caches; names are free-form. |  | [service](#service) |
| platform | One product as a namespace, for one target segment, app or domain; named with functional groups such as sulfoxide. |  | [service tree](#service-tree-1), [service](#service) |
| service | An API or application, usually one git repo; named with elements of the periodic table. |  | [platform](#platform), [module](#module) |
| service tree | The naming scheme landscape, platform, service, module; LCPSM adds the cluster, which LPSM omits as Kubernetes-specific. | LPSM, LCPSM | [landscape](#landscape), [cluster](#cluster), [platform](#platform), [service](#service), [module](#module) |

## cluster

**Meaning**

A Kubernetes cluster within one landscape, unique within that landscape. It enables blue-green deployments and fallback clusters, and lets you switch clusters without affecting other labels. Named with gemstones.

**Examples**

From `docs/standards/service-tree/index.md`: `diamond`, `ruby`, `sapphire`, `emerald`. No example in this template yet: no file here sets a cluster.

## landscape

**Meaning**

The deployment environment, encoding purpose, region and segment. Named with Pokemon: a legendary is meta or administration, a first evolution is development, a second evolution is staging or UAT, a final evolution is production, and a non-evolution is local or testing.

**Examples**

From `docs/standards/service-tree/index.md`: `pichu` is development, `pikachu` is staging and `raichu` is production.

## module

**Meaning**

An actual component of a service. There are no theme restrictions on its name.

**Examples**

From `docs/standards/service-tree/index.md`: `api`, `worker`, `database`, `cache`, `queue`.

## platform

**Meaning**

A single product as a namespace: the same target segment, a single app or a single domain from a business view. Named with functional groups.

**Examples**

From `docs/standards/service-tree/index.md`: `sulfoxide` for system services, `halogen` for business services and `noble-gas` for infrastructure services.

## service

**Meaning**

An API or application, usually one git repository. Normal services loosely follow element mappings; services of the `sulfoxide` platform follow them strictly.

**Examples**

From `docs/standards/service-tree/index.md`: `hydrogen`, `carbon` and `iron`.

## service tree

**Meaning**

The naming scheme that confines every product and application resource, so resources of one product are easy to query and classify. LCPSM is the tech-specific form and includes the cluster for Kubernetes; LPSM is the domain form and omits the cluster as Kubernetes-specific metadata. It is used in resource names (`{l}-{c}-{p}-{s}-{m}`), labels and tags, and repository names.

**Examples**

From `docs/standards/service-tree/index.md`, the labels example:

```yaml
labels:
  landscape: pichu
  cluster: diamond
  platform: sulfoxide
  service: hydrogen
  module: api
```
