---
id: documentation
title: How We Document
---

# How We Document

Docs say what is true now. Why and when live in git history and ADRs.

## Kinds of doc

| Kind     | Holds                                    | Lives in                         |
| -------- | ---------------------------------------- | -------------------------------- |
| Standard | how we do one thing                      | `docs/standards/<name>/index.md` |
| Domain   | one bounded context: its model and rules | `docs/domain/<name>/`            |
| Plugin   | one plugin: purpose, seam and tests      | the plugin's own folder          |
| ADR      | one decision, its options and why        | `docs/adr/NNNN-<slug>.md`        |

Standards, domain docs and plugin docs are final state only. This tree keeps the
plural `docs/standards/` folder.

## Final state and history

- A doc describes how things are now.
- No "previously", no dated notes, no "changed in".
- History is git history and ADRs.
- A word that changes meaning: edit its entry; the ADR says why.

## ADR

An ADR is a short dated record of one decision, its options and why.

- Lives in `docs/adr/`, named `NNNN-<slug>.md`.
- `NNNN` is a four-digit number that counts up.
- A decision that changes gets a new ADR; the old one stays as written.

## Ubiquitous language

A UL is the official word list of one area. Inside the area a word means one thing.
People, code and LLMs use that word for that thing.

| Area     | File                            | Namespace                                   |
| -------- | ------------------------------- | ------------------------------------------- |
| Standard | `docs/standards/<name>/UL.yaml` | `durian.cloud/engineering/standards/<name>` |
| Domain   | `docs/domain/<name>/UL.yaml`    | `durian.cloud/<product>/<name>`             |
| Plugin   | `<plugin folder>/UL.yaml`       | `durian.cloud/<product>/<context>/<plugin>` |

- `docs/standards/UL.yaml` (namespace `durian.cloud/engineering/standards`) holds
  words used across standards.
- Every `UL.yaml` has one namespace; no two files share one.
- The `ul` tool scans every file named exactly `UL.yaml` and overlays them into one
  UL. There are no imports.
- `ul gen` writes `UL.md` beside each `UL.yaml`. Never edit a `UL.md` by hand.
- CI and the `a-ul` hook run `ul check`; CI also runs `ul gen --check`.

### Entry fields

| Field     | Rule                                          |
| --------- | --------------------------------------------- |
| `desc`    | one line, at most 160 characters, plain words |
| `aliases` | other names for the same thing                |
| `avoid`   | wrong synonyms the docs really use            |
| `see`     | other words that relate to this one           |

`details`, `status` and `replacedBy` are the other fields.

### When a word changes

| Change | Do                                                      |
| ------ | ------------------------------------------------------- |
| Add    | a new word in the right `UL.yaml`, in a PR              |
| Change | edit its entry in place                                 |
| Retire | keep it with `status: retired` and `replacedBy: <word>` |

A word a doc already says in a standard is added from what the standard says. A
word not yet in a `UL.yaml` is not official. A vague word stays out until its
standard is clear.

## Bounded context

A bounded context is an area with its own UL where a word has one meaning. The same
word in two contexts may mean two things; each context keeps its own `UL.yaml`. Where
two contexts meet, one side translates; neither imports the other's internal types.

## Plugin

A plugin is a bounded context in its own folders. It joins the core at one
registration point, a single line appended to a list. It carries its own
`UL.yaml`, owns its types and imports no other plugin's internal model. Adding a
plugin edits no shared code beyond that line.
