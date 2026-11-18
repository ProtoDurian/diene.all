# infisical

durian.cloud > engineering > standards > infisical

How secrets are read and scanned with Infisical

| Word | Means | Also called | See |
|---|---|---|---|
| session | A usable Infisical login on this machine; scripts/local/secrets.sh makes sure one exists and logs in only when there is none. |  | [subprocess form](#subprocess-form) |
| subprocess form | infisical run --env=dev -- command; secrets exist only inside the command it runs, never in the parent shell. |  | [session](#session) |

## session

## subprocess form
