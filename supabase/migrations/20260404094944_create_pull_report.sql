-- Replace sync_runs with pull_report

DROP FUNCTION IF EXISTS ads_v2.create_sync_run(text, text);
DROP FUNCTION IF EXISTS ads_v2.finalize_sync(text, text);
DROP TABLE IF EXISTS ads_v2.sync_runs;

CREATE TABLE ads_v2.pull_report (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  customer_id     text NOT NULL,
  status          text NOT NULL DEFAULT 'running',
  started_at      timestamptz NOT NULL DEFAULT now(),
  completed_at    timestamptz,
  results         jsonb,
  errors          jsonb,

  CONSTRAINT valid_pull_status CHECK (status IN ('running', 'completed', 'failed'))
);

ALTER TABLE ads_v2.pull_report ENABLE ROW LEVEL SECURITY;

-- Start a pull: called at the beginning of the script
CREATE OR REPLACE FUNCTION ads_v2.start_pull(p_pull_id text, p_customer_id text)
RETURNS void AS $$
BEGIN
  INSERT INTO ads_v2.pull_report (id, customer_id)
  VALUES (p_pull_id::uuid, p_customer_id)
  ON CONFLICT (id) DO NOTHING;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Complete a pull: called at the end of the script with results
CREATE OR REPLACE FUNCTION ads_v2.complete_pull(
  p_pull_id text,
  p_customer_id text,
  p_results jsonb DEFAULT NULL,
  p_errors jsonb DEFAULT NULL
)
RETURNS void AS $$
BEGIN
  UPDATE ads_v2.pull_report
  SET
    status = CASE
      WHEN p_errors IS NOT NULL AND jsonb_array_length(p_errors) > 0 THEN 'failed'
      ELSE 'completed'
    END,
    completed_at = now(),
    results = p_results,
    errors = p_errors
  WHERE id = p_pull_id::uuid;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
