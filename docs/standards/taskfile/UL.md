# taskfile

durian.cloud > engineering > standards > taskfile

How the one repository task runner is organised

| Word | Means | Also called | See |
|---|---|---|---|
| includes | The block in Taskfile.yaml that maps each namespace to a file under tasks/; a task shown as namespace:task is the task key in that file. |  | [task](#task) |
| setup | The root task that owns generated workspace assets; it runs skills-sync sync, the only permitted vendor-tree writer. |  | [task](#task) |
| task | The go-task runner, the only task runner; task --list prints every task with its description. |  | [includes](#includes), [setup](#setup) |

## includes

## setup

## task
