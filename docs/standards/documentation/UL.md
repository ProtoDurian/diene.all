# documentation

durian.cloud > engineering > standards > documentation

How we write standards, domain docs, decisions and word lists

| Word | Means | Also called | See |
|---|---|---|---|
| ADR | A short record of one decision, its options and why; a decision that changes gets a new ADR and the old one stays as written. |  | [final state](#final-state) |
| domain | The docs of one domain in docs/domain/<name>/, final state only, with its own UL.yaml. |  | [UL](#ul), [final state](#final-state) |
| final state | How a doc describes things now; why and when live in git history and ADRs. |  | [ADR](#adr) |
| namespace | The name of one UL, such as durian.cloud/engineering/standards/documentation; one namespace per file, and no two files share one. |  | [UL](#ul) |
| standard | How we do one thing, as it is now, in docs/standards/<name>/index.md; it has a UL.yaml beside it. |  | [UL](#ul), [final state](#final-state) |
| UL | The official word list of one area; inside the area a word means one thing, and people, code and LLMs use it for that thing. | ubiquitous language | [namespace](#namespace), [standard](#standard), [domain](#domain) |

## ADR

## domain

## final state

## namespace

## standard

## UL

One UL is one `UL.yaml`. The `ul` tool scans every file named exactly `UL.yaml` and overlays them into one UL. There are no imports.
