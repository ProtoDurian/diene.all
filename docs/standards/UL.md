# standards

durian.cloud > engineering > standards

Words every standard uses about this template and how it is inherited

| Word | Means | Also called | See |
|---|---|---|---|
| descendant | A repository or template built from this one; it adds its own parts, such as images, charts and language setup. | downstream | [workspace](#workspace), [strip](#strip) |
| gate | A check that refuses a change; hooks in nix/pre-commit.nix are gates, and local commits, task lint and CI run the same ones. |  |  |
| strip | A descendant variant that removes one part of this template; each part stays self-contained so a strip takes out only its own. |  | [descendant](#descendant) |
| vendored skills | Skills in .claude/skills/vendor/, written only by skills-sync and never by hand. |  | [workspace](#workspace) |
| workspace | This template, the base every descendant inherits; it names no runtime. |  | [descendant](#descendant) |

## descendant

## gate

## strip

## vendored skills

## workspace
