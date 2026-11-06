# Sealed secrets

Secrets live in the repository, encrypted with [SOPS](https://getsops.io) and
[age](https://age-encryption.org). Key names stay readable; every value is
`ENC[...]`. Anyone with the age private key can open them; CI needs only that key.

## Files

| Path                            | What                                                             |
| ------------------------------- | ---------------------------------------------------------------- |
| `.sops.yaml`                    | Which age recipients `secrets/*.yaml` are encrypted to           |
| `secrets/production.yaml`       | The deployed Worker's secrets and the infrastructure credentials |
| `scripts/local/secrets-init.sh` | Creates your age key and re-seals `secrets/` to it               |
| `scripts/validate/secrets.sh`   | Proves nothing is in plain text and the key sets agree           |

Each `secrets/<env>.yaml` holds the same flat set of keys:

| Key                                                | Used by                                       |
| -------------------------------------------------- | --------------------------------------------- |
| `BETTER_AUTH_SECRET`                               | Worker (session signing)                      |
| `S3_ACCESS_KEY_ID`, `S3_SECRET_ACCESS_KEY`         | Worker (its own Tigris key)                   |
| `GITHUB_CLIENT_ID`, `GITHUB_CLIENT_SECRET`         | Worker (GitHub sign-in)                       |
| `GOOGLE_CLIENT_ID`, `GOOGLE_CLIENT_SECRET`         | Worker (Google sign-in)                       |
| `MAIL_API_KEY`                                     | Worker (mail provider)                        |
| `CLOUDFLARE_API_TOKEN`, `NEON_API_KEY`             | OpenTofu providers                            |
| `TIGRIS_ACCESS_KEY_ID`, `TIGRIS_SECRET_ACCESS_KEY` | OpenTofu Tigris provider and its state bucket |

## First use

The template ships sealed to a recipient whose private key exists nowhere, so
nobody can open it. Make the files yours:

```bash
./scripts/local/secrets-init.sh   # creates ~/.config/sops/age/keys.txt if missing
sops edit secrets/production.yaml # replace the random placeholders with real values
```

The init script writes your public key into `.sops.yaml`. A file your key can
already open is re-encrypted with its values kept; a file it cannot open is
re-sealed under the same key names with random placeholder values.

To give a teammate access, add their age public key to `.sops.yaml` (a YAML list
or comma-separated) and run `sops updatekeys secrets/production.yaml`.

## CI

Store the contents of your age key file as the `SOPS_AGE_KEY` repository secret.
`sops` reads it from the environment; no other secret store is needed.

## Adding a secret

A secret is one key in three places, and the check fails until all agree:

1. `sops edit secrets/<env>.yaml` and add `NEW_KEY` in every env file.
2. Add `variable "new_key"` with `sensitive = true` in `infra/tofu/variables.tf`.
3. For a Worker secret, also add `NEW_KEY = var.new_key` to the `worker_secrets`
   output in `infra/tofu/outputs.tf` and `NEW_KEY` to `secrets.required` in
   `wrangler.jsonc` (top level and `env.production`).

## What the check enforces

`scripts/validate/secrets.sh`:

- every value in `secrets/*.yaml` is `ENC[...]` and the files carry a SOPS MAC;
- every env file has the same keys;
- sealed keys equal the OpenTofu `sensitive` variables (upper-cased);
- `worker_secrets` keys equal `secrets.required` in every `wrangler.jsonc` env;
- no age private key, `.env`, `.dev.vars`, `*.agekey` or state file is in the tree,
  and no `*.tfvars` sets a sensitive variable;
- when your age key opens a file, none of its decrypted values appears anywhere
  else in the tree.

Never write a decrypted value to disk. Feed it through a pipe or process
substitution, as the commands in [the infrastructure guide](aseity-infra.md) do.
