# conventional-commits

durian.cloud > engineering > standards > conventional-commits

How commit messages are written so releases follow from them

| Word | Means | Also called | See |
|---|---|---|---|
| breaking change | A change marked with ! after the type or scope, or with a footer keyword from the keywords list in release.yaml. |  | [commit type](#commit-type) |
| commit type | The word before the colon in a commit subject; release.yaml lists each type with a desc saying when to use it. | type | [scope](#scope), [release level](#release-level) |
| release level | The version bump a scope causes, the release value in release.yaml; major, minor, patch, or false for no release. |  | [scope](#scope) |
| scope | The optional word in parentheses after a type; the valid ones are listed per type, and default applies when none is written. |  | [commit type](#commit-type), [special scope](#special-scope), [release level](#release-level) |
| special scope | A scope usable with any type, listed under specialScopes in release.yaml. |  | [scope](#scope) |

## breaking change

## commit type

## release level

## scope

## special scope
