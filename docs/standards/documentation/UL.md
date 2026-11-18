# documentation

durian.cloud > engineering > standards > documentation

How we write standards, domain docs, decisions and word lists

| Word | Means | Also called | See |
|---|---|---|---|
| ADR | A short dated record of one decision, its options and why; lives in docs/adr/ as NNNN-<slug>.md and is not edited once written. | architecture decision record | [final state](#final-state) |
| bounded context | An area with its own UL where a word has one meaning; the same word in another context may mean something else. |  | [UL](#ul), [plugin](#plugin), [domain](#domain) |
| domain | The docs of one bounded context in docs/domain/<name>/, final state only, with its own UL.yaml. |  | [bounded context](#bounded-context), [UL](#ul) |
| final state | How a doc describes things now; why and when live in git history and ADRs. |  | [ADR](#adr) |
| namespace | The name of one UL, such as durian.cloud/engineering/standards/documentation; one namespace per file, and no two files share one. |  | [UL](#ul) |
| plugin | A bounded context in its own folders that joins the core at one registration point and carries its own UL.yaml. |  | [bounded context](#bounded-context), [UL](#ul) |
| retired word | A word no longer used; it stays in its UL.yaml with status retired and replacedBy, so old text still resolves. |  | [UL](#ul) |
| standard | How we do one thing, as it is now, in docs/standards/<name>/index.md; it has a UL.yaml beside it. |  | [UL](#ul), [final state](#final-state) |
| UL | The official word list of one area; inside the area a word means one thing, and people, code and LLMs use it for that thing. | ubiquitous language | [namespace](#namespace), [standard](#standard), [domain](#domain), [plugin](#plugin), [retired word](#retired-word) |

## ADR

## bounded context

## domain

## final state

## namespace

## plugin

## retired word

## standard

## UL

One UL is one `UL.yaml`. The `ul` tool scans every file named exactly `UL.yaml` and overlays them into one UL. There are no imports.
