# Snapshots must be on from creation: the fork command uses Tigris's native bucket fork.
resource "tigris_bucket" "files" {
  bucket          = var.bucket_name
  enable_snapshot = true
}
