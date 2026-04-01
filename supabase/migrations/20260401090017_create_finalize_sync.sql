CREATE OR REPLACE FUNCTION ads.finalize_sync(
  p_customer_id text,
  p_sync_id text
) RETURNS void AS $$
BEGIN
  -- Acquire advisory lock for this customer (transaction-scoped)
  PERFORM pg_advisory_xact_lock(hashtext(p_customer_id));

  -- Mark unseen asset_links as REMOVED
  UPDATE ads.asset_links
  SET link_status = 'REMOVED', updated_at = now()
  WHERE customer_id = p_customer_id
    AND last_sync_id IS DISTINCT FROM p_sync_id::uuid
    AND link_status != 'REMOVED';

  -- Refresh cascade view
  REFRESH MATERIALIZED VIEW CONCURRENTLY ads.cascade_status;

  -- Mark sync as completed
  UPDATE ads.sync_runs
  SET status = 'completed', completed_at = now()
  WHERE id = p_sync_id::uuid;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
