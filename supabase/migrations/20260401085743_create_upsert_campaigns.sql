CREATE OR REPLACE FUNCTION ads.upsert_campaigns(
  p_customer_id text,
  p_sync_id text,
  p_rows jsonb
) RETURNS void AS $$
BEGIN
  INSERT INTO ads.campaigns (
    campaign_id, customer_id, name, status, serving_status,
    channel_type, channel_sub_type, bidding_strategy,
    start_date, end_date, budget_amount_micros,
    last_checked_at, last_sync_id
  )
  SELECT
    (r->>'campaignId')::bigint,
    p_customer_id,
    r->>'name',
    r->>'status',
    r->>'servingStatus',
    r->>'channelType',
    r->>'channelSubType',
    r->>'biddingStrategy',
    (r->>'startDate')::date,
    (r->>'endDate')::date,
    (r->>'budgetAmountMicros')::bigint,
    now(),
    p_sync_id::uuid
  FROM jsonb_array_elements(p_rows) AS r
  ON CONFLICT (campaign_id, customer_id)
  DO UPDATE SET
    name = EXCLUDED.name,
    status = EXCLUDED.status,
    serving_status = EXCLUDED.serving_status,
    channel_type = EXCLUDED.channel_type,
    channel_sub_type = EXCLUDED.channel_sub_type,
    bidding_strategy = EXCLUDED.bidding_strategy,
    start_date = EXCLUDED.start_date,
    end_date = EXCLUDED.end_date,
    budget_amount_micros = EXCLUDED.budget_amount_micros,
    last_checked_at = now(),
    last_sync_id = EXCLUDED.last_sync_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
