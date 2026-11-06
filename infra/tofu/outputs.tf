output "hyperdrive_id" {
  description = "Goes into the HYPERDRIVE binding's id in wrangler.jsonc."
  value       = cloudflare_hyperdrive_config.app.id
}

output "neon_project_id" {
  description = "Neon project the fork command branches from."
  value       = neon_project.app.id
}

output "neon_branch_id" {
  description = "Neon branch that holds production data."
  value       = neon_project.app.default_branch_id
}

output "bucket_name" {
  description = "Tigris bucket the fork command copies."
  value       = tigris_bucket.files.bucket
}

output "worker_secrets" {
  sensitive = true
  value = {
    BETTER_AUTH_SECRET   = var.better_auth_secret
    S3_ACCESS_KEY_ID     = var.s3_access_key_id
    S3_SECRET_ACCESS_KEY = var.s3_secret_access_key
    GITHUB_CLIENT_ID     = var.github_client_id
    GITHUB_CLIENT_SECRET = var.github_client_secret
    GOOGLE_CLIENT_ID     = var.google_client_id
    GOOGLE_CLIENT_SECRET = var.google_client_secret
    MAIL_API_KEY         = var.mail_api_key
  }
}
