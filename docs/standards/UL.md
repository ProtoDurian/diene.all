# standards

durian.cloud > engineering > standards

Words every standard uses about this template and how it is inherited

| Word | Means | Also called | See |
|---|---|---|---|
| descendant | Built from this template; it owns its own Dockerfiles and charts. | downstream | [workspace](#workspace), [strip](#strip) |
| gate | A check that refuses a change; local commits, task lint and CI all run the same gates. |  |  |
| strip | A downstream removal of an included part; each include stays self-contained so a strip removes only its own. |  | [descendant](#descendant) |
| vendored skills | The skills in the vendor tree; skills-sync sync is its only writer, and CI enforces them through the a-skills-sync hook. |  | [workspace](#workspace) |
| workspace | This template; it names no runtime. |  | [descendant](#descendant) |

## descendant

## gate

## strip

## vendored skills

## workspace
