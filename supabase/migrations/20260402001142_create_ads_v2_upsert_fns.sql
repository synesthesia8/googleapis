CREATE OR REPLACE FUNCTION ads_v2.upsert_accounts(p_customer_id text, p_sync_id text, p_rows jsonb)
RETURNS void AS $$
BEGIN
  INSERT INTO ads_v2.accounts (customer_id, data, last_sync_id, last_checked_at)
  SELECT p_customer_id, r, p_sync_id::uuid, now()
  FROM jsonb_array_elements(p_rows) AS r
  ON CONFLICT (customer_id) DO UPDATE SET
    data = EXCLUDED.data, last_sync_id = EXCLUDED.last_sync_id, last_checked_at = now(), updated_at = now();
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION ads_v2.upsert_campaigns(p_customer_id text, p_sync_id text, p_rows jsonb)
RETURNS void AS $$
BEGIN
  INSERT INTO ads_v2.campaigns (campaign_id, customer_id, data, last_sync_id, last_checked_at)
  SELECT (r->'campaign'->>'id')::bigint, p_customer_id, r, p_sync_id::uuid, now()
  FROM jsonb_array_elements(p_rows) AS r
  ON CONFLICT (campaign_id, customer_id) DO UPDATE SET
    data = EXCLUDED.data, last_sync_id = EXCLUDED.last_sync_id, last_checked_at = now(), updated_at = now();
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION ads_v2.upsert_ad_groups(p_customer_id text, p_sync_id text, p_rows jsonb)
RETURNS void AS $$
BEGIN
  INSERT INTO ads_v2.ad_groups (ad_group_id, customer_id, data, last_sync_id, last_checked_at)
  SELECT (r->'adGroup'->>'id')::bigint, p_customer_id, r, p_sync_id::uuid, now()
  FROM jsonb_array_elements(p_rows) AS r
  ON CONFLICT (ad_group_id, customer_id) DO UPDATE SET
    data = EXCLUDED.data, last_sync_id = EXCLUDED.last_sync_id, last_checked_at = now(), updated_at = now();
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION ads_v2.upsert_ads(p_customer_id text, p_sync_id text, p_rows jsonb)
RETURNS void AS $$
BEGIN
  INSERT INTO ads_v2.ads (ad_id, customer_id, data, last_sync_id, last_checked_at)
  SELECT (r->'adGroupAd'->'ad'->>'id')::bigint, p_customer_id, r, p_sync_id::uuid, now()
  FROM jsonb_array_elements(p_rows) AS r
  ON CONFLICT (ad_id, customer_id) DO UPDATE SET
    data = EXCLUDED.data, last_sync_id = EXCLUDED.last_sync_id, last_checked_at = now(), updated_at = now();
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION ads_v2.upsert_assets(p_customer_id text, p_sync_id text, p_rows jsonb)
RETURNS void AS $$
BEGIN
  INSERT INTO ads_v2.assets (asset_id, customer_id, data, last_sync_id, last_checked_at)
  SELECT (r->'asset'->>'id')::bigint, p_customer_id, r, p_sync_id::uuid, now()
  FROM jsonb_array_elements(p_rows) AS r
  ON CONFLICT (asset_id, customer_id) DO UPDATE SET
    data = EXCLUDED.data, last_sync_id = EXCLUDED.last_sync_id, last_checked_at = now(), updated_at = now();
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION ads_v2.upsert_customer_assets(p_customer_id text, p_sync_id text, p_rows jsonb)
RETURNS void AS $$
BEGIN
  INSERT INTO ads_v2.customer_assets (customer_id, asset_id, field_type, data, last_sync_id, last_checked_at)
  SELECT p_customer_id, (r->'asset'->>'id')::bigint, r->'customerAsset'->>'fieldType', r, p_sync_id::uuid, now()
  FROM jsonb_array_elements(p_rows) AS r
  ON CONFLICT (customer_id, asset_id, field_type) DO UPDATE SET
    data = EXCLUDED.data, last_sync_id = EXCLUDED.last_sync_id, last_checked_at = now(), updated_at = now();
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION ads_v2.upsert_campaign_assets(p_customer_id text, p_sync_id text, p_rows jsonb)
RETURNS void AS $$
BEGIN
  INSERT INTO ads_v2.campaign_assets (customer_id, campaign_id, asset_id, field_type, data, last_sync_id, last_checked_at)
  SELECT p_customer_id, (r->'campaign'->>'id')::bigint, (r->'asset'->>'id')::bigint, r->'campaignAsset'->>'fieldType', r, p_sync_id::uuid, now()
  FROM jsonb_array_elements(p_rows) AS r
  ON CONFLICT (customer_id, campaign_id, asset_id, field_type) DO UPDATE SET
    data = EXCLUDED.data, last_sync_id = EXCLUDED.last_sync_id, last_checked_at = now(), updated_at = now();
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION ads_v2.upsert_ad_group_assets(p_customer_id text, p_sync_id text, p_rows jsonb)
RETURNS void AS $$
BEGIN
  INSERT INTO ads_v2.ad_group_assets (customer_id, ad_group_id, asset_id, field_type, data, last_sync_id, last_checked_at)
  SELECT p_customer_id, (r->'adGroup'->>'id')::bigint, (r->'asset'->>'id')::bigint, r->'adGroupAsset'->>'fieldType', r, p_sync_id::uuid, now()
  FROM jsonb_array_elements(p_rows) AS r
  ON CONFLICT (customer_id, ad_group_id, asset_id, field_type) DO UPDATE SET
    data = EXCLUDED.data, last_sync_id = EXCLUDED.last_sync_id, last_checked_at = now(), updated_at = now();
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION ads_v2.upsert_ad_group_ad_asset_view(p_customer_id text, p_sync_id text, p_rows jsonb)
RETURNS void AS $$
BEGIN
  INSERT INTO ads_v2.ad_group_ad_asset_view (customer_id, ad_group_id, ad_id, asset_id, field_type, data, last_sync_id, last_checked_at)
  SELECT p_customer_id, (r->'adGroup'->>'id')::bigint, (r->'adGroupAd'->'ad'->>'id')::bigint, (r->'asset'->>'id')::bigint, r->'adGroupAdAssetView'->>'fieldType', r, p_sync_id::uuid, now()
  FROM jsonb_array_elements(p_rows) AS r
  ON CONFLICT (customer_id, ad_group_id, ad_id, asset_id, field_type) DO UPDATE SET
    data = EXCLUDED.data, last_sync_id = EXCLUDED.last_sync_id, last_checked_at = now(), updated_at = now();
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION ads_v2.create_sync_run(p_sync_id text, p_customer_id text)
RETURNS void AS $$
BEGIN
  INSERT INTO ads_v2.sync_runs (id, customer_id)
  VALUES (p_sync_id::uuid, p_customer_id)
  ON CONFLICT (id) DO NOTHING;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION ads_v2.finalize_sync(p_customer_id text, p_sync_id text)
RETURNS void AS $$
BEGIN
  UPDATE ads_v2.sync_runs
  SET status = 'completed', completed_at = now()
  WHERE id = p_sync_id::uuid;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
