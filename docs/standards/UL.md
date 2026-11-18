# standards

durian.cloud > engineering > standards

Words every engineering standard uses about this template and how it is inherited

| Word | Means | Also called | See |
|---|---|---|---|
| descendant | Built from this template; it owns its own Dockerfiles and charts. | downstream | [workspace template](#workspace-template), [strip](#strip) |
| quality gate | A check that refuses a change; local commits, task lint and CI all run the same quality gates. |  |  |
| strip | A downstream removal of an included part; each include stays self-contained so a strip removes only its own. |  | [descendant](#descendant) |
| vendored skills | The skills in the vendor tree; skills-sync sync is its only writer, and CI enforces them through the a-skills-sync hook. |  | [workspace template](#workspace-template) |
| workspace template | This template; it names no runtime. |  | [descendant](#descendant) |

## descendant

**Meaning**

Something built from the workspace template. It owns its own Dockerfiles and charts, and it fills what this template leaves empty, such as `release.hooks.prepare`.

**Examples**

From `docs/standards/semantic-release/index.md`: a downstream node fills `release.hooks.prepare` to stamp the version into a file its ecosystem versions.

## quality gate

**Meaning**

A check that refuses a change. Local commits, `task lint` and CI all run the same quality gates, because they are the pre-commit hooks of `nix/pre-commit.nix`.

**Examples**

- `a-workflows`, the quality gate on workflow wiring.
- The `a-ul` hook in `nix/pre-commit.nix` is the quality gate on the UL.
- `task lint` runs `pre-commit run --all-files` (`Taskfile.yaml`).

## strip

**Meaning**

A downstream removal of a part this template includes. Each include stays self-contained, so a strip removes only its own part.

**Examples**

No example in this template yet: a strip happens in a descendant, not here.

## vendored skills

**Meaning**

The skills in `.claude/skills/vendor/`. `skills-sync sync` is its only writer, and humans never edit it. CI enforces them through the `a-skills-sync` hook (`skills-sync sync --frozen`). The workspace template names no runtime, so the vendor tree is empty here.

**Examples**

`.claude/skills/vendor/manifest.json` holds `[]`. `scripts/local/setup.sh` runs `skills-sync sync`.

## workspace template

**Meaning**

This template, which every engineering standard describes. It names no runtime, so work that depends on a language runtime, such as the vendored skills sync, is deliberately inert here. A descendant is built from it.

**Examples**

- `docs/standards/shell-scripts/index.md` opens with "the conventions for shell scripts in the workspace template".
- `infra/root_chart/values.yaml` sets `service: workspace` and `platform: diene`.
