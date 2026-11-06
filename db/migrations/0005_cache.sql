CREATE TABLE cache_entries (
  tenant_id uuid NOT NULL DEFAULT app_current_tenant() REFERENCES tenants (id) ON DELETE CASCADE,
  key text NOT NULL,
  value jsonb NOT NULL,
  expires_at timestamptz NOT NULL,
  PRIMARY KEY (tenant_id, key)
);

CREATE INDEX cache_entries_expires_idx ON cache_entries (expires_at);

ALTER TABLE cache_entries ENABLE ROW LEVEL SECURITY;
ALTER TABLE cache_entries FORCE ROW LEVEL SECURITY;

CREATE POLICY cache_entries_tenant ON cache_entries TO app_runtime
  USING (tenant_id = app_current_tenant())
  WITH CHECK (tenant_id = app_current_tenant());
CREATE POLICY cache_entries_system ON cache_entries TO app_system
  USING (true) WITH CHECK (true);

GRANT SELECT, INSERT, UPDATE, DELETE ON cache_entries TO app_runtime, app_system;
