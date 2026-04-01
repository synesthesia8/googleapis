CREATE OR REPLACE FUNCTION ads.create_sync_run(
  p_sync_id text,
  p_customer_id text
) RETURNS void AS $$
BEGIN
  INSERT INTO ads.sync_runs (id, customer_id, is_first_sync)
  VALUES (
    p_sync_id::uuid,
    p_customer_id,
    NOT EXISTS (SELECT 1 FROM ads.sync_runs WHERE customer_id = p_customer_id AND status = 'completed')
  )
  ON CONFLICT (id) DO NOTHING;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
