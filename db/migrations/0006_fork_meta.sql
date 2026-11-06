CREATE TABLE fork_meta (
  singleton boolean PRIMARY KEY DEFAULT true CHECK (singleton),
  is_fork boolean NOT NULL DEFAULT false,
  source text,
  forked_at timestamptz
);

INSERT INTO fork_meta (singleton, is_fork) VALUES (true, false);

GRANT SELECT ON fork_meta TO app_runtime, app_system;
