#!/usr/bin/env bash
set -euo pipefail

root_dir="$(git rev-parse --show-toplevel)"
cd "${root_dir}"

tfvars="infra/tofu/production.tfvars"
worker_name="$(awk -F '"' '/^worker_name[[:space:]]*=/ { print $2 }' "${tfvars}")"
app_hostname="$(awk -F '"' '/^app_hostname[[:space:]]*=/ { print $2 }' "${tfvars}")"
bucket_name="$(awk -F '"' '/^bucket_name[[:space:]]*=/ { print $2 }' "${tfvars}")"
tigris_endpoint="$(awk -F '"' '/^tigris_endpoint[[:space:]]*=/ { print $2 }' "${tfvars}")"
[ -z "${worker_name}" ] || [ -z "${app_hostname}" ] || [ -z "${bucket_name}" ] || [ -z "${tigris_endpoint}" ] &&
  echo "❌ ${tfvars} must set worker_name, app_hostname, bucket_name and tigris_endpoint" >&2 && exit 1
sealed_keys="$(yq -o=json '[del(.sops) | keys | .[]]' secrets/production.yaml)"

assets_dir="$(bun -e 'process.stdout.write(Bun.JSONC.parse(await Bun.file("wrangler.jsonc").text()).assets?.directory ?? "")')"
[ -n "${assets_dir}" ] && mkdir -p "${assets_dir}"
out_dir="$(mktemp -d)"
trap 'rm -rf "${out_dir}"' EXIT

echo '🔨 Parsing and bundling wrangler.jsonc (wrangler deploy --dry-run --env "")...'
wrangler deploy --dry-run --env "" --outdir "${out_dir}/top" >/dev/null
echo "🔨 Parsing and bundling the production environment (wrangler deploy --dry-run --env production)..."
wrangler deploy --dry-run --env production --outdir "${out_dir}/production" >/dev/null

echo "📝 Comparing wrangler.jsonc bindings and vars with infra/tofu and secrets/..."
problems="$(bun -e 'process.stdout.write(JSON.stringify(Bun.JSONC.parse(await Bun.file("wrangler.jsonc").text())))' |
  jq -r --arg worker "${worker_name}" --arg host "${app_hostname}" --arg bucket "${bucket_name}" \
    --arg endpoint "${tigris_endpoint}" --argjson sealed "${sealed_keys}" '
    def hyperdrive: [(.hyperdrive // [])[] | .binding];
    def configs: [{ where: "top level", c: . }, { where: "env.production", c: (.env.production // {}) }];
    (.env.production // null) as $prod
    | (.vars // {} | keys) as $top_vars
    | [
        (if $prod == null then "env.production is missing; it is the deployed Worker" else empty end),
        (configs[] | .where as $w | .c
          | (if hyperdrive != ["HYPERDRIVE"]
              then "\($w): the only hyperdrive binding must be HYPERDRIVE (found [\(hyperdrive | join(","))])" else empty end),
            (if ((.routes // []) | length) > 0 or .route != null
              then "\($w): routes are owned by infra/tofu (cloudflare_workers_custom_domain); remove them here" else empty end),
            ((.vars // {} | keys) as $v
              | (if $v != $top_vars then "\($w): vars [\($v | join(","))] differ from the top level [\($top_vars | join(","))]" else empty end),
                ($v - ($v - $sealed) | if length > 0 then "\($w): sealed secrets must not be plain vars: \(join(","))" else empty end))),
        (if $prod != null then
          (if $prod.name != $worker then "env.production.name must be \($worker) (worker_name in infra/tofu)" else empty end),
          (if $prod.vars.APP_URL != "https://\($host)" then "env.production APP_URL must be https://\($host) (app_hostname in infra/tofu)" else empty end),
          (if $prod.vars.S3_BUCKET != $bucket then "env.production S3_BUCKET must be \($bucket) (bucket_name in infra/tofu)" else empty end),
          (if $prod.vars.S3_ENDPOINT != $endpoint then "env.production S3_ENDPOINT must be \($endpoint) (tigris_endpoint in infra/tofu)" else empty end)
        else empty end)
      ] | .[] | "❌ wrangler.jsonc: \(.)"')"
[ -n "${problems}" ] && echo "${problems}" >&2 && exit 1

echo "✅ wrangler.jsonc matches infra/tofu and the sealed secrets"
