CREATE TABLE notes (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v7(),
  tenant_id uuid NOT NULL DEFAULT app_current_tenant() REFERENCES tenants (id) ON DELETE CASCADE,
  title text NOT NULL,
  body text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX notes_tenant_created_idx ON notes (tenant_id, created_at DESC);

ALTER TABLE notes ENABLE ROW LEVEL SECURITY;
ALTER TABLE notes FORCE ROW LEVEL SECURITY;

CREATE POLICY notes_tenant ON notes TO app_runtime
  USING (tenant_id = app_current_tenant())
  WITH CHECK (tenant_id = app_current_tenant());

GRANT SELECT, INSERT, UPDATE, DELETE ON notes TO app_runtime;
