-- Drop unused columns from accounts
ALTER TABLE ads.accounts DROP COLUMN IF EXISTS is_mcc;
ALTER TABLE ads.accounts DROP COLUMN IF EXISTS mcc_customer_id;
ALTER TABLE ads.accounts DROP COLUMN IF EXISTS status;
ALTER TABLE ads.accounts DROP COLUMN IF EXISTS currency_code;
ALTER TABLE ads.accounts DROP COLUMN IF EXISTS time_zone;

-- Update upsert function to match
CREATE OR REPLACE FUNCTION ads.upsert_accounts(
  p_customer_id text,
  p_sync_id text,
  p_rows jsonb
) RETURNS void AS $$
BEGIN
  INSERT INTO ads.accounts (customer_id, descriptive_name)
  SELECT
    p_customer_id,
    r->>'descriptiveName'
  FROM jsonb_array_elements(p_rows) AS r
  ON CONFLICT (customer_id)
  DO UPDATE SET
    descriptive_name = EXCLUDED.descriptive_name,
    updated_at = now();
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
