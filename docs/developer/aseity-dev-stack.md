# Local development stack

`compose.dev.yaml` runs what the Worker talks to in production, locally:

| Service    | Stands in for | Default address                                  |
| ---------- | ------------- | ------------------------------------------------ |
| `postgres` | Neon (17)     | `postgres://aseity:aseity@127.0.0.1:5432/aseity` |
| `minio`    | Tigris (S3)   | `http://127.0.0.1:9000`, console on `:9001`      |

The `minio` service creates the bucket on start and only reports healthy once it
exists. It is development only: no image is built or pushed, and nothing here is
deployed.

```bash
docker compose -f compose.dev.yaml up -d --wait   # start, wait until healthy
docker compose -f compose.dev.yaml down           # stop (add -v to wipe data)
```

`wrangler dev` reaches Postgres through the `localConnectionString` of the
`HYPERDRIVE` binding in `wrangler.jsonc`, and MinIO through the top-level vars.
The defaults above match them.

## Running several stacks

Ports and the project name come from the environment, so parallel checkouts do
not clash:

| Variable                                         | Default      |
| ------------------------------------------------ | ------------ |
| `ASEITY_DEV_STACK`                               | `aseity-dev` |
| `ASEITY_DEV_PG_PORT`                             | `5432`       |
| `ASEITY_DEV_S3_PORT`                             | `9000`       |
| `ASEITY_DEV_S3_CONSOLE_PORT`                     | `9001`       |
| `ASEITY_DEV_PG_USER` / `_PASSWORD` / `_DATABASE` | `aseity`     |
| `ASEITY_DEV_S3_ACCESS_KEY_ID`                    | `aseity`     |
| `ASEITY_DEV_S3_SECRET_ACCESS_KEY`                | `aseity-dev` |
| `ASEITY_DEV_S3_BUCKET`                           | `aseity`     |

```bash
ASEITY_DEV_STACK=feature-x ASEITY_DEV_PG_PORT=55432 ASEITY_DEV_S3_PORT=59000 \
  ASEITY_DEV_S3_CONSOLE_PORT=59001 docker compose -f compose.dev.yaml up -d --wait
```

When you change a port, point `wrangler dev` at it with
`CLOUDFLARE_HYPERDRIVE_LOCAL_CONNECTION_STRING_HYPERDRIVE` and a `.dev.vars`
`S3_ENDPOINT` override (`.dev.vars` is git-ignored).

The MinIO image is the community-maintained `pgsty/minio` build: upstream MinIO
no longer publishes container images.
