# service-tree

durian.cloud > engineering > standards > service-tree

The naming scheme that places every product resource in one tree

| Word | Means | Also called | See |
|---|---|---|---|
| cluster | A Kubernetes cluster inside one landscape, unique within it; named with gemstones. |  | [landscape](#landscape) |
| landscape | The deployment environment, by purpose, region and segment; named with Pokemon, such as pichu, pikachu and raichu. |  | [service tree](#service-tree-1), [cluster](#cluster) |
| module | An actual component of a service, such as an api, worker, database, cache or queue; names are free-form. |  | [service](#service) |
| platform | One product as a namespace, for one target segment, app or domain; named with functional groups such as sulfoxide. |  | [service tree](#service-tree-1), [service](#service) |
| service | An API or application, usually one git repo; named with elements of the periodic table. |  | [platform](#platform), [module](#module) |
| service tree | The naming scheme landscape, platform, service, module; LCPSM adds the cluster, which LPSM omits as Kubernetes-specific. | LPSM, LCPSM | [landscape](#landscape), [cluster](#cluster), [platform](#platform), [service](#service), [module](#module) |

## cluster

## landscape

## module

## platform

## service

## service tree
