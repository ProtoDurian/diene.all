# nix

durian.cloud > engineering > standards > nix

How the nix folder composes packages, shells, formatters and hooks

| Word | Means | Also called | See |
|---|---|---|---|
| environment group | A named list of packages in nix/env.nix that shells compose with ++. | group | [shell](#shell), [nix registry](#nix-registry) |
| nix registry | Where a package that needs building belongs; this tree consumes it by name in nix/packages.nix and never builds one. | registry | [environment group](#environment-group) |
| PATH_add | A .envrc line for a path whose existence a file checked into the repository declares; a dev convenience. |  |  |
| shell | A named development environment in nix/shells.nix, built from environment groups and entered with nix develop .#name. |  | [environment group](#environment-group), [shellHook](#shellhook) |
| shellHook | Passed to a shell that runs the git hooks, which inherits it; never customize or override it in nix/shells.nix. |  | [shell](#shell) |

## environment group

## nix registry

## PATH_add

## shell

## shellHook
