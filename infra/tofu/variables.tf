variable "worker_name" {
  description = "Cloudflare Worker name; must equal `name` in wrangler.jsonc."
  type        = string
}

variable "app_hostname" {
  description = "Public hostname the Worker serves; APP_URL in wrangler.jsonc is https://<this>."
  type        = string
}

variable "cloudflare_account_id" {
  description = "Cloudflare account that owns the Worker and the Hyperdrive config."
  type        = string
}

variable "cloudflare_zone_name" {
  description = "Cloudflare zone (apex domain) that holds app_hostname."
  type        = string
}

variable "neon_region_id" {
  description = "Neon region, for example aws-us-east-2."
  type        = string
}

variable "neon_org_id" {
  description = "Neon organization that owns the project; null uses the API key's default."
  type        = string
  default     = null
}

variable "database_name" {
  description = "Postgres database the Worker connects to through Hyperdrive."
  type        = string
}

variable "database_owner" {
  description = "Neon role that owns the database and that Hyperdrive signs in as."
  type        = string
}

variable "bucket_name" {
  description = "Tigris bucket for files; must equal S3_BUCKET in wrangler.jsonc."
  type        = string
}

variable "tigris_endpoint" {
  description = "Tigris S3 endpoint; must equal S3_ENDPOINT in wrangler.jsonc."
  type        = string
}

variable "cloudflare_api_token" {
  description = "Cloudflare API token with Workers, Hyperdrive and DNS edit rights."
  type        = string
  sensitive   = true
}

variable "neon_api_key" {
  description = "Neon API key."
  type        = string
  sensitive   = true
}

variable "tigris_access_key_id" {
  description = "Tigris access key used by OpenTofu to manage the bucket."
  type        = string
  sensitive   = true
}

variable "tigris_secret_access_key" {
  description = "Tigris secret key used by OpenTofu to manage the bucket."
  type        = string
  sensitive   = true
}

variable "better_auth_secret" {
  description = "Worker secret BETTER_AUTH_SECRET: signs Better Auth sessions."
  type        = string
  sensitive   = true
}

variable "s3_access_key_id" {
  description = "Worker secret S3_ACCESS_KEY_ID: the Worker's own bucket access key."
  type        = string
  sensitive   = true
}

variable "s3_secret_access_key" {
  description = "Worker secret S3_SECRET_ACCESS_KEY: the Worker's own bucket secret key."
  type        = string
  sensitive   = true
}

variable "github_client_id" {
  description = "Worker secret GITHUB_CLIENT_ID: GitHub OAuth app client id."
  type        = string
  sensitive   = true
}

variable "github_client_secret" {
  description = "Worker secret GITHUB_CLIENT_SECRET: GitHub OAuth app client secret."
  type        = string
  sensitive   = true
}

variable "google_client_id" {
  description = "Worker secret GOOGLE_CLIENT_ID: Google OAuth client id."
  type        = string
  sensitive   = true
}

variable "google_client_secret" {
  description = "Worker secret GOOGLE_CLIENT_SECRET: Google OAuth client secret."
  type        = string
  sensitive   = true
}

variable "mail_api_key" {
  description = "Worker secret MAIL_API_KEY: HTTP mail provider key."
  type        = string
  sensitive   = true
}
