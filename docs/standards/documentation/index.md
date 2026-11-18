---
id: documentation
title: How We Document
---

# How We Document

Docs say what is true now. Why and when live in git history and ADRs.

## Kinds of doc

| Kind                 | Holds                  | Lives in                         |
| -------------------- | ---------------------- | -------------------------------- |
| Engineering standard | how we do one thing    | `docs/standards/<name>/index.md` |
| Domain docs          | the docs of one domain | `docs/domain/<name>/`            |

Engineering standards and domain docs are final state only. This tree keeps the plural
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

| Area                 | File                            | UL namespace                                |
| -------------------- | ------------------------------- | ------------------------------------------- |
| Engineering standard | `docs/standards/<name>/UL.yaml` | `durian.cloud/engineering/standards/<name>` |
| Domain docs          | `docs/domain/<name>/UL.yaml`    | `durian.cloud/<product>/<name>`             |
| Plugin               | in the plugin's own folder      | its own, one per file                       |

- `docs/standards/UL.yaml` (UL namespace `durian.cloud/engineering/standards`) holds
  words used across engineering standards.
- Every `UL.yaml` has one UL namespace; no two files share one.
- The `ul` tool scans every file named exactly `UL.yaml` and overlays them into one
  UL. There are no imports.
- `ul gen` writes `UL.md` beside each `UL.yaml`. Never edit a `UL.md` by hand.
- The `a-ul` pre-commit hook runs `ul check`, the word check below, then `ul gen --check`; the Pre-Commit CI job runs it with every other pre-commit hook, so there is no UL job.
- Every word in a `UL.yaml`, or one of its aliases, appears in the docs of its own
  engineering standard; the `a-ul` pre-commit hook checks it.

### Entry fields

| Field     | Rule                                                                                                                                           |
| --------- | ---------------------------------------------------------------------------------------------------------------------------------------------- |
| `desc`    | one line, at most 160 characters, plain words                                                                                                  |
| `aliases` | other names for the same thing                                                                                                                 |
| `avoid`   | wrong synonyms the docs really use                                                                                                             |
| `see`     | other words that relate to this one                                                                                                            |
| `details` | markdown with a **Meaning** part and an **Examples** part; each example is a real command, path or snippet from this tree, with its file named |

The ul spec has more fields (`status`, `replacedBy`) and allows retiring
a word.

### When a word changes

| Change | Do                                         |
| ------ | ------------------------------------------ |
| Add    | a new word in the right `UL.yaml`, in a PR |
| Change | edit its entry in place                    |

A word is added from what its engineering standard already says. A word not yet in a
`UL.yaml` is not official.

Name a word for its own area (a `local tag suffix`, not a bare `suffix`), so that no
word is overloaded across areas.
