# conventional-commits

durian.cloud > engineering > standards > conventional-commits

How commit messages are written so releases follow from them

| Word | Means | Also called | See |
|---|---|---|---|
| breaking change | A change marked with ! after the type or scope, or with a footer keyword from the keywords list in release.yaml. |  | [commit type](#commit-type) |
| commit type | The word before the colon in a commit subject; release.yaml lists each type with a desc saying when to use it. | type | [scope](#scope), [version bump](#version-bump) |
| scope | A word in parentheses after the type; the valid ones are listed per type, and default applies when none is written. |  | [commit type](#commit-type), [specialScopes](#specialscopes), [version bump](#version-bump) |
| specialScopes | The top-level list in release.yaml of scopes usable with any type. |  | [scope](#scope) |
| version bump | What a scope's release value in release.yaml causes; major, minor, patch, or false for no release. |  | [scope](#scope) |

## breaking change

## commit type

## scope

## specialScopes

## version bump
