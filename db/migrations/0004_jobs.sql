CREATE TABLE jobs (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v7(),
  tenant_id uuid NOT NULL DEFAULT app_current_tenant() REFERENCES tenants (id) ON DELETE CASCADE,
  kind text NOT NULL,
  payload jsonb NOT NULL DEFAULT '{}'::jsonb,
  status text NOT NULL DEFAULT 'queued' CHECK (status IN ('queued', 'running', 'done', 'failed', 'held')),
  outside_effect boolean NOT NULL DEFAULT false,
  run_at timestamptz NOT NULL DEFAULT now(),
  attempts integer NOT NULL DEFAULT 0,
  locked_until timestamptz,
  last_error text,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX jobs_claim_idx ON jobs (run_at, id) WHERE status IN ('queued', 'running');

ALTER TABLE jobs ENABLE ROW LEVEL SECURITY;
ALTER TABLE jobs FORCE ROW LEVEL SECURITY;

CREATE POLICY jobs_tenant ON jobs TO app_runtime
  USING (tenant_id = app_current_tenant())
  WITH CHECK (tenant_id = app_current_tenant());
CREATE POLICY jobs_system ON jobs TO app_system
  USING (true) WITH CHECK (true);

GRANT SELECT, INSERT ON jobs TO app_runtime;
GRANT SELECT, INSERT, UPDATE, DELETE ON jobs TO app_system;
