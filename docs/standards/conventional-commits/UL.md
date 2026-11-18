# conventional-commits

durian.cloud > engineering > standards > conventional-commits

How commit messages are written so releases follow from them

| Word | Means | Also called | See |
|---|---|---|---|
| breaking change | A change marked with ! after the type or commit scope, or with a footer keyword from the keywords list in release.yaml. |  | [commit type](#commit-type) |
| commit scope | A word in parentheses after the type; the valid ones are listed per type, and default applies when none is written. |  | [commit type](#commit-type), [specialScopes](#specialscopes), [version bump](#version-bump) |
| commit type | The word before the colon in a commit subject; release.yaml lists each type with a desc saying when to use it. |  | [commit scope](#commit-scope), [version bump](#version-bump) |
| specialScopes | The top-level list in release.yaml of commit scopes usable with any type. |  | [commit scope](#commit-scope) |
| version bump | What a commit scope's release value in release.yaml causes; major, minor, patch, or false for no release. |  | [commit scope](#commit-scope) |

## breaking change

**Meaning**

A change marked with `!` after the type or commit scope, or with a footer that starts with a keyword from the `keywords:` list in `release.yaml`.

**Examples**

From `release.yaml`:

```yaml
keywords:
  - BREAKING CHANGE
  - BREAKING CHANGES
  - BREAKING
```

`docs/standards/conventional-commits/index.md` describes the `!` form: add `!` after the type or commit scope.

## commit scope

**Meaning**

A word in parentheses after the commit type, as in `dep(patch):`. Each type's `scopes:` map in `release.yaml` lists the valid ones; `default:` applies when you write no commit scope at all. Each commit scope's `release:` value is the version bump it causes.

**Examples**

From `release.yaml`, the `dep` type:

```yaml
scopes:
  default:
    desc: Update a dependency
    release: false
  patch:
    desc: Patch dependency update
    release: patch
```

`docs/standards/conventional-commits/index.md` gives `dep(patch):` as the form of a commit scope; it releases a patch.

## commit type

**Meaning**

The word before the colon in a commit subject. Each entry under `types:` in `release.yaml` has a `type:` and a `desc:` saying when to use it; the `a-releaser-commit` commit-msg pre-commit hook lints messages with `releaser lint-commit -c release.yaml`.

**Examples**

From `release.yaml`:

```yaml
- type: ci
  desc: CI/CD changes
  scopes:
    default:
      desc: Update CI/CD
      release: false
```

## specialScopes

**Meaning**

The top-level `specialScopes:` map in `release.yaml`. Its commit scopes can be used with any type, instead of being listed under one type.

**Examples**

From `release.yaml`:

```yaml
specialScopes:
  no-release:
    desc: Prevent release from happening
    release: false
```

`no-release` can follow any type, and its `release: false` means no release.

## version bump

**Meaning**

The effect a commit scope's `release:` value in `release.yaml` has on the version: `major`, `minor`, `patch`, or `false` for no release.

**Examples**

From `release.yaml`:

```yaml
- type: test
  desc: Test changes
  section: 🧪 Tests 🧪
  scopes:
    default:
      desc: Add or correct tests
      release: minor
```

A `test:` commit causes a minor bump; `dep(major):` causes a major one.
