CREATE OR REPLACE FUNCTION ads.upsert_ad_groups(
  p_customer_id text,
  p_sync_id text,
  p_rows jsonb
) RETURNS void AS $$
BEGIN
  INSERT INTO ads.ad_groups (
    ad_group_id, customer_id, campaign_id, name, status, type, cpc_bid_micros,
    last_checked_at, last_sync_id
  )
  SELECT
    (r->>'adGroupId')::bigint,
    p_customer_id,
    (r->>'campaignId')::bigint,
    r->>'name',
    r->>'status',
    r->>'type',
    (r->>'cpcBidMicros')::bigint,
    now(),
    p_sync_id::uuid
  FROM jsonb_array_elements(p_rows) AS r
  ON CONFLICT (ad_group_id, customer_id)
  DO UPDATE SET
    campaign_id = EXCLUDED.campaign_id,
    name = EXCLUDED.name,
    status = EXCLUDED.status,
    type = EXCLUDED.type,
    cpc_bid_micros = EXCLUDED.cpc_bid_micros,
    last_checked_at = now(),
    last_sync_id = EXCLUDED.last_sync_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
