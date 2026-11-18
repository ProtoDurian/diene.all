# taskfile

durian.cloud > engineering > standards > taskfile

How the one repository task runner is organised

| Word | Means | Also called | See |
|---|---|---|---|
| setup task | The root task that owns generated workspace assets; it runs skills-sync sync, the only writer of the vendor tree. |  | [task](#task) |
| task | The go-task runner, the only task runner; task --list prints every task with its desc. |  | [task namespace](#task-namespace) |
| task namespace | The key in the includes block of Taskfile.yaml that maps to a file under tasks/; a task shown as namespace:task is the task key in that file. |  | [task](#task) |

## setup task

## task

## task namespace
