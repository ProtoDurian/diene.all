# documentation

durian.cloud > engineering > standards > documentation

How we write engineering standards, domain docs, decisions and word lists

| Word | Means | Also called | See |
|---|---|---|---|
| ADR | A short record of one decision, its options and why; a decision that changes gets a new ADR and the old one stays as written. |  | [final state](#final-state) |
| domain docs | The docs of one domain in docs/domain/<name>/, final state only, with its own UL.yaml. |  | [UL](#ul), [final state](#final-state) |
| engineering standard | How we do one thing, as it is now, in docs/standards/<name>/index.md; it has a UL.yaml beside it. |  | [UL](#ul), [final state](#final-state) |
| final state | How a doc describes things now; why and when live in git history and ADRs. |  | [ADR](#adr) |
| UL | The official word list of one area; inside the area a word means one thing, and people, code and LLMs use it for that thing. | ubiquitous language | [UL namespace](#ul-namespace), [engineering standard](#engineering-standard), [domain docs](#domain-docs) |
| UL namespace | The name of one UL, such as durian.cloud/engineering/standards/documentation; one UL namespace per file, and no two files share one. |  | [UL](#ul) |

## ADR

**Meaning**

A short record of one decision, its options and why. A decision that changes gets a new ADR; the old one stays as written. Why and when live in git history and ADRs, not in the docs.

**Examples**

No example in this template yet: the tree holds no ADR.

## domain docs

**Meaning**

The docs of one domain, in `docs/domain/<name>/`. They are final state only and have their own `UL.yaml`, with the namespace `durian.cloud/<product>/<name>`.

**Examples**

No example in this template yet: `docs/domain/` holds only `README.md`.

## engineering standard

**Meaning**

A doc that says how we do one thing, as it is now. It lives at `docs/standards/<name>/index.md`, is final state only, and has a `UL.yaml` beside it. This tree keeps the plural `docs/standards/` folder. `CLAUDE.md` links each one, and a thin skill under `.claude/skills/` routes to it.

**Examples**

- `docs/standards/taskfile/index.md` and its `docs/standards/taskfile/UL.yaml`.
- `CLAUDE.md` has a `# Documentation` section that points at `docs/standards/documentation/index.md`.
- The skill `.claude/skills/documentation/SKILL.md` routes back to it.

## final state

**Meaning**

A doc says how things are now. It has no "previously", no dated notes and no "changed in". History is git history and ADRs. Engineering standards and domain docs are final state only.

**Examples**

Every `docs/standards/<name>/index.md` is written this way, for example `docs/standards/linting/index.md`, which says what runs and how, not what ran before.

## UL

**Meaning**

The official word list of one area. Inside the area a word means one thing, and people, code and LLMs use that word for that thing. One UL is one `UL.yaml`; the `ul` tool scans every file named exactly `UL.yaml` and overlays them into one UL. There are no imports. A word is added from what its engineering standard already says; a word not yet in a `UL.yaml` is not official. Name a word for its own area so that no word is overloaded.

**Examples**

- `docs/standards/taskfile/UL.yaml` is the UL of the taskfile engineering standard.
- `ul all --format md` prints the whole overlaid UL.
- `ul lookup go-task --from docs/standards/taskfile/index.md` looks one word up.

## UL namespace

**Meaning**

The name of one UL. Every `UL.yaml` has one UL namespace, and no two files share one. An engineering standard's namespace is `durian.cloud/engineering/standards/<name>`; a domain docs namespace is `durian.cloud/<product>/<name>`.

**Examples**

From `docs/standards/documentation/UL.yaml`:

```yaml
namespace: durian.cloud/engineering/standards/documentation
```

From `docs/standards/UL.yaml`, the file for words used across engineering standards: `namespace: durian.cloud/engineering/standards`.
