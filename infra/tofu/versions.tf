terraform {
  required_version = "~> 1.11"

  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 5.28"
    }
    neon = {
      source  = "kislerdm/neon"
      version = "~> 0.18"
    }
    tigris = {
      source  = "tigrisdata/tigris"
      version = "~> 1.1"
    }
  }

  # State lives in a private Tigris bucket created once by hand. The bucket name comes from
  # `-backend-config=bucket=<name>` and credentials from AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY
  # at init time, so nothing about the backend's access is stored here.
  backend "s3" {
    key                         = "aseity/terraform.tfstate"
    region                      = "auto"
    endpoints                   = { s3 = "https://t3.storage.dev" }
    use_lockfile                = true
    skip_credentials_validation = true
    skip_region_validation      = true
    skip_requesting_account_id  = true
    skip_metadata_api_check     = true
    skip_s3_checksum            = true
  }
}
