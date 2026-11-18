---
id: documentation
title: How We Document
---

# How We Document

Docs say what is true now. Why and when live in git history and ADRs.

## Kinds of doc

| Kind     | Holds                  | Lives in                         |
| -------- | ---------------------- | -------------------------------- |
| Standard | how we do one thing    | `docs/standards/<name>/index.md` |
| Domain   | the docs of one domain | `docs/domain/<name>/`            |

Standards and domain docs are final state only. This tree keeps the plural
`docs/standards/` folder.

## Final state and history

- A doc describes how things are now.
- No "previously", no dated notes, no "changed in".
- History is git history and ADRs.

## ADR

An ADR is a short record of one decision, its options and why.

- A decision that changes gets a new ADR; the old one stays as written.

## Ubiquitous language

A UL is the official word list of one area. Inside the area a word means one thing.
People, code and LLMs use that word for that thing.

| Area     | File                            | Namespace                                   |
| -------- | ------------------------------- | ------------------------------------------- |
| Standard | `docs/standards/<name>/UL.yaml` | `durian.cloud/engineering/standards/<name>` |
| Domain   | `docs/domain/<name>/UL.yaml`    | `durian.cloud/<product>/<name>`             |
| Plugin   | in the plugin's own folder      | its own, one per file                       |

- `docs/standards/UL.yaml` (namespace `durian.cloud/engineering/standards`) holds
  words used across standards.
- Every `UL.yaml` has one namespace; no two files share one.
- The `ul` tool scans every file named exactly `UL.yaml` and overlays them into one
  UL. There are no imports.
- `ul gen` writes `UL.md` beside each `UL.yaml`. Never edit a `UL.md` by hand.
- CI and the `a-ul` hook run `ul check`; CI also runs `ul gen --check`.
- Every word and alias in a `UL.yaml` appears in the docs of its own standard;
  CI checks it.

### Entry fields

| Field     | Rule                                          |
| --------- | --------------------------------------------- |
| `desc`    | one line, at most 160 characters, plain words |
| `aliases` | other names for the same thing                |
| `avoid`   | wrong synonyms the docs really use            |
| `see`     | other words that relate to this one           |

The ul spec has more fields (`details`, `status`, `replacedBy`) and allows retiring
a word.

### When a word changes

| Change | Do                                         |
| ------ | ------------------------------------------ |
| Add    | a new word in the right `UL.yaml`, in a PR |
| Change | edit its entry in place                    |

A word is added from what its standard already says. A word not yet in a
`UL.yaml` is not official.
