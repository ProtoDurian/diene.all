CREATE TABLE tenants (
  id uuid PRIMARY KEY,
  slug text NOT NULL UNIQUE,
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'suspended')),
  created_at timestamptz NOT NULL DEFAULT now(),
  approved_at timestamptz
);

ALTER TABLE tenants ENABLE ROW LEVEL SECURITY;
ALTER TABLE tenants FORCE ROW LEVEL SECURITY;

CREATE POLICY tenants_runtime_read ON tenants FOR SELECT TO app_runtime
  USING (id = app_current_tenant());
CREATE POLICY tenants_system ON tenants TO app_system
  USING (true) WITH CHECK (true);

GRANT SELECT ON tenants TO app_runtime;
GRANT SELECT, INSERT, UPDATE, DELETE ON tenants TO app_system;
