CREATE OR REPLACE FUNCTION ads.upsert_accounts(
  p_customer_id text,
  p_sync_id text,
  p_rows jsonb
) RETURNS void AS $$
BEGIN
  INSERT INTO ads.accounts (
    customer_id, descriptive_name, currency_code, time_zone,
    is_mcc, mcc_customer_id, status
  )
  SELECT
    p_customer_id,
    r->>'descriptiveName',
    r->>'currencyCode',
    r->>'timeZone',
    (r->>'isMcc')::boolean,
    r->>'mccCustomerId',
    r->>'status'
  FROM jsonb_array_elements(p_rows) AS r
  ON CONFLICT (customer_id)
  DO UPDATE SET
    descriptive_name = EXCLUDED.descriptive_name,
    currency_code = EXCLUDED.currency_code,
    time_zone = EXCLUDED.time_zone,
    is_mcc = EXCLUDED.is_mcc,
    mcc_customer_id = EXCLUDED.mcc_customer_id,
    status = EXCLUDED.status,
    updated_at = now();
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
