# nix

durian.cloud > engineering > standards > nix

How the nix folder composes packages, shells, formatters and hooks

| Word | Means | Also called | See |
|---|---|---|---|
| environment group | A named list of packages in nix/env.nix that shells compose with ++. | group | [shell](#shell), [nix registry](#nix-registry) |
| nix registry | The source of tools and builders; nix/packages.nix consumes a package by name and never builds one. | registry | [environment group](#environment-group) |
| PATH_add | A line in .envrc that adds a path whose existence a repo file declares; never used to install tools or export variables. |  |  |
| shell | A named development environment in nix/shells.nix, built from environment groups and entered with nix develop .#name. |  | [environment group](#environment-group), [shellHook](#shellhook) |
| shellHook | The hook installer a shell inherits so git hooks are installed; never customize or override it in nix/shells.nix. |  | [shell](#shell) |

## environment group

## nix registry

## PATH_add

## shell

## shellHook
