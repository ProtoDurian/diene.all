# infisical

durian.cloud > engineering > standards > infisical

How secrets are read and scanned with Infisical

| Word | Means | Also called | See |
|---|---|---|---|
| Infisical session | A usable Infisical login on this machine; scripts/local/secrets.sh makes sure one exists and logs in only when there is none. |  | [subprocess form](#subprocess-form) |
| subprocess form | infisical run --env=dev -- command; secrets exist only inside the command it runs, never in the parent shell. |  | [Infisical session](#infisical-session) |

## Infisical session

**Meaning**

A login to Infisical that works on this machine. You need one before the subprocess form can read secrets. `scripts/local/secrets.sh` takes no arguments, writes no files and is safe to run again; it logs in only when there is no Infisical session yet. `INFISICAL_API_URL` selects the instance and defaults to `https://secrets.atomi.cloud`.

**Examples**

Make sure there is one:

```bash
./scripts/local/secrets.sh
```

The check inside `scripts/local/secrets.sh`:

```bash
if infisical user get token --silent >/dev/null 2>&1; then
  echo "✅ Already logged into Infisical at ${api_url}"
  exit 0
fi
```

## subprocess form

**Meaning**

The one way to read secrets: run the command under `infisical run`. The secrets are available only inside that subprocess and never reach the parent shell or a file on disk. A `.env` file is a copy of your secrets that nothing keeps current, so do not export them into one.

**Examples**

From `docs/standards/infisical/index.md`:

```bash
infisical run --env=dev -- task lint
```
