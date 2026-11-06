# Infrastructure

OpenTofu in `infra/tofu/` owns the cloud resources; `wrangler` owns the Worker's
code. Both read the same values, and `scripts/validate/wrangler.sh` fails when
they drift.

| File                  | Manages                                                                     |
| --------------------- | --------------------------------------------------------------------------- |
| `neon.tf`             | Neon project (Postgres 17), its `main` branch, the owner role, the database |
| `cloudflare.tf`       | Hyperdrive config pointing at Neon; the Worker custom domain (DNS + TLS)    |
| `tigris.tf`           | The files bucket, with snapshots on so the fork command can fork it         |
| `variables.tf`        | Every input; secrets are `sensitive` and come only from `secrets/`          |
| `production.tfvars`   | Non-secret values for production                                            |
| `outputs.tf`          | Hyperdrive id, Neon ids, bucket name, and the Worker secrets map            |
| `.terraform.lock.hcl` | Provider versions and hashes (Linux and macOS, amd64 and arm64)             |

## What must match

`wrangler.jsonc` has a top level for local development and `env.production` for
the deployed Worker. Between them and `production.tfvars`:

| wrangler.jsonc                      | infra/tofu                            |
| ----------------------------------- | ------------------------------------- |
| `env.production.name`               | `worker_name`                         |
| `env.production.vars.APP_URL`       | `https://` + `app_hostname`           |
| `env.production.vars.S3_BUCKET`     | `bucket_name`                         |
| `env.production.vars.S3_ENDPOINT`   | `tigris_endpoint`                     |
| `hyperdrive[0].binding` (every env) | always `HYPERDRIVE`, the only binding |
| `env.production.hyperdrive[0].id`   | `tofu output -raw hyperdrive_id`      |
| `secrets.required` (every env)      | keys of the `worker_secrets` output   |

`wrangler.jsonc` declares no `routes`: the custom domain belongs to OpenTofu.

## State

State is kept in a private Tigris bucket that you create once by hand (for
example `aseity-tofu-state`). Nothing about it is in the tree: the bucket name is
passed at init and the credentials come from `secrets/`.

## Deploying

Run from `infra/tofu`. Decrypted values only travel through the environment or
process substitution, never a file.

```bash
cd infra/tofu
export AWS_ACCESS_KEY_ID="$(sops decrypt --extract '["TIGRIS_ACCESS_KEY_ID"]' ../../secrets/production.yaml)"
export AWS_SECRET_ACCESS_KEY="$(sops decrypt --extract '["TIGRIS_SECRET_ACCESS_KEY"]' ../../secrets/production.yaml)"
tofu init -backend-config=bucket=aseity-tofu-state

secret_vars() {
  sops decrypt --output-type json ../../secrets/production.yaml |
    jq -r 'to_entries[] | "\(.key | ascii_downcase) = \(.value | tojson)"'
}
```

First deploy, in this order (the custom domain needs the Worker to exist):

1. `tofu apply -var-file=production.tfvars -var-file=<(secret_vars) -target=cloudflare_hyperdrive_config.app -target=tigris_bucket.files`
2. Put `tofu output -raw hyperdrive_id` into `env.production.hyperdrive[0].id`
   in `wrangler.jsonc` and commit it (it is not a secret).
3. `wrangler deploy --env production` (from the repo root).
4. `tofu apply -var-file=production.tfvars -var-file=<(secret_vars)`
5. `tofu output -json worker_secrets | wrangler secret bulk --env production`

After that, `tofu apply` for infrastructure changes, `wrangler deploy --env
production` for code, and step 5 whenever a Worker secret changes.

## Database role

Hyperdrive signs in as the Neon owner role created here. Roles made through the
Neon API join `neon_superuser`, so tenant isolation must not rest on that role's
attributes: request code switches to the migrations' non-owner application role
(`SET LOCAL ROLE`) inside each request transaction.

## Checks

```bash
./scripts/validate/tofu.sh       # tofu fmt -check, init -backend=false, validate
./scripts/validate/wrangler.sh   # wrangler deploy --dry-run, then the table above
./scripts/validate/secrets.sh    # see aseity-secrets.md
```
