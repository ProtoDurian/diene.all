data "cloudflare_zone" "app" {
  filter = {
    name = var.cloudflare_zone_name
  }
}

# Hyperdrive pools to Neon's direct (non-pooler) host; it is the Worker's only database route.
# Query caching stays off so no result can be served across tenants.
resource "cloudflare_hyperdrive_config" "app" {
  account_id = var.cloudflare_account_id
  name       = var.worker_name

  origin = {
    scheme   = "postgres"
    host     = neon_project.app.database_host
    port     = 5432
    database = neon_database.app.name
    user     = neon_role.owner.name
    password = neon_role.owner.password
  }

  caching = {
    disabled = true
  }
}

# Creates the proxied DNS record and certificate for app_hostname. The Worker itself is
# uploaded by `wrangler deploy`, which must have run once before this applies.
resource "cloudflare_workers_custom_domain" "app" {
  account_id = var.cloudflare_account_id
  zone_id    = data.cloudflare_zone.app.zone_id
  hostname   = var.app_hostname
  service    = var.worker_name
}
