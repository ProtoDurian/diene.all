resource "neon_project" "app" {
  name       = var.worker_name
  pg_version = 17
  region_id  = var.neon_region_id
  org_id     = var.neon_org_id

  branch {
    name = "main"
  }
}

resource "neon_role" "owner" {
  project_id = neon_project.app.id
  branch_id  = neon_project.app.default_branch_id
  name       = var.database_owner
}

resource "neon_database" "app" {
  project_id = neon_project.app.id
  branch_id  = neon_project.app.default_branch_id
  name       = var.database_name
  owner_name = neon_role.owner.name
}
