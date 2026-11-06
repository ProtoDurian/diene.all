# Installing `aseity`

`aseity` is the app's command-line tool: `aseity migrate` applies the database migrations and
`aseity fork create / list / delete` manages forks. It ships as a standalone binary (no Bun or
Node runtime needed) for Linux (x64, arm64), macOS (arm64) and Windows (x64). Each release
pushes a Debian package to the Gemfury account `atomicloud`, a cask to `AtomiCloud/homebrew-tap`
and a manifest to `AtomiCloud/scoop-bucket`.

> **macOS caveat — unsigned binaries.** The binaries are not code-signed. On macOS, Gatekeeper
> quarantines them on first run. Clear the quarantine attribute after a manual install:
>
> ```bash
> xattr -d com.apple.quarantine "$(command -v aseity)"
> ```

## Debian / Ubuntu (`.deb`)

The `atomicloud` Gemfury repository does not currently publish a GPG key. Do not add it to APT
with signature verification disabled. Until repository signing is provisioned, download the
matching `aseity_<version>_linux_<amd64-or-arm64>.deb` and `checksums.txt` assets from the same
[GitHub release](https://github.com/AtomiCloud/diene.aseity/releases), then verify and install:

```bash
package='aseity_<version>_linux_<amd64-or-arm64>.deb'
grep " ${package}$" checksums.txt | sha256sum --check
sudo apt install "./${package}"
```

## Homebrew (macOS)

```bash
brew install --cask atomicloud/tap/aseity
```

The cask strips the macOS quarantine attribute on install, so no `xattr` step is needed.

## Scoop (Windows)

```powershell
scoop bucket add atomicloud https://github.com/AtomiCloud/scoop-bucket
scoop install atomicloud/aseity
```

## Nix

```bash
nix run github:AtomiCloud/diene.aseity#aseity -- --help
```

## One-line installer (Linux and macOS)

Downloads the right archive for your OS and architecture, verifies its checksum, and installs to
`~/.local/bin` (override with `BIN_DIR`, pin a release with `VERSION=v1.2.3`):

```bash
curl -fsSL --connect-timeout 30 --max-time 600 https://github.com/AtomiCloud/diene.aseity/releases/latest/download/install.sh | bash
```

Or download `aseity_<os>_<arch>.tar.gz` (`.zip` on Windows) from the
[releases page](https://github.com/AtomiCloud/diene.aseity/releases), verify it against
`checksums.txt`, and put the `aseity` binary on your `PATH`.

## Verify

```bash
aseity --version
aseity --help
```

## Configure

`aseity` reads its settings from `ASEITY_` environment variables; `__` separates nested keys.

| Variable                                                                           | Meaning                                                                        |
| ---------------------------------------------------------------------------------- | ------------------------------------------------------------------------------ |
| `ASEITY_DATABASE__URL`                                                             | Source database URL, as the database owner (used by `migrate` and local forks) |
| `ASEITY_DATABASE__PROVIDER`                                                        | `local` (default, `CREATE DATABASE … TEMPLATE`) or `neon` (branch API)         |
| `ASEITY_DATABASE__NEON__API_KEY`, `__PROJECT_ID`, `__DATABASE_NAME`, `__ROLE_NAME` | Neon project to branch; `__PARENT_BRANCH_ID` picks a parent branch             |
| `ASEITY_STORAGE__PROVIDER`                                                         | `copy` (default, copies every object) or `tigris` (native fork)                |
| `ASEITY_STORAGE__ENDPOINT`, `__REGION`, `__BUCKET`                                 | S3-compatible store and the source bucket                                      |
| `ASEITY_STORAGE__ACCESS_KEY_ID`, `__SECRET_ACCESS_KEY`                             | Store credentials                                                              |

A local fork needs every client of the source database disconnected (stop `wrangler dev`
first). A Tigris fork needs a source bucket created with snapshots enabled.

`aseity fork create <name>` writes the fork's new auth secret, database connection string and
bucket name to `.env.fork-<name>` (mode 0600; `--secret-file` picks another path). Keep that
file out of git. The fork signs everyone out, disables every API key, deletes stored tokens and
signing keys, rotates OAuth client secrets, holds jobs with outside effects and marks itself as a
fork, so its Worker never sends real email.
