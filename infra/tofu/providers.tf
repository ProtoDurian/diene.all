provider "cloudflare" {
  api_token = var.cloudflare_api_token
}

provider "neon" {
  api_key = var.neon_api_key
}

provider "tigris" {
  endpoint   = var.tigris_endpoint
  access_key = var.tigris_access_key_id
  secret_key = var.tigris_secret_access_key
}
