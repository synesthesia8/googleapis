CREATE OR REPLACE FUNCTION ads.upsert_ads(
  p_customer_id text,
  p_sync_id text,
  p_rows jsonb
) RETURNS void AS $$
BEGIN
  INSERT INTO ads.ads (
    ad_id, customer_id, ad_group_id, ad_type, status,
    approval_status, review_status, ad_strength, policy_topics, final_urls,
    last_checked_at, last_sync_id
  )
  SELECT
    (r->>'adId')::bigint,
    p_customer_id,
    (r->>'adGroupId')::bigint,
    r->>'adType',
    r->>'status',
    r->>'approvalStatus',
    r->>'reviewStatus',
    r->>'adStrength',
    (r->'policyTopics')::jsonb,
    CASE WHEN r->'finalUrls' IS NOT NULL
      THEN ARRAY(SELECT jsonb_array_elements_text(r->'finalUrls'))
      ELSE NULL
    END,
    now(),
    p_sync_id::uuid
  FROM jsonb_array_elements(p_rows) AS r
  ON CONFLICT (ad_id, customer_id)
  DO UPDATE SET
    ad_group_id = EXCLUDED.ad_group_id,
    ad_type = EXCLUDED.ad_type,
    status = EXCLUDED.status,
    approval_status = EXCLUDED.approval_status,
    review_status = EXCLUDED.review_status,
    ad_strength = EXCLUDED.ad_strength,
    policy_topics = EXCLUDED.policy_topics,
    final_urls = EXCLUDED.final_urls,
    last_checked_at = now(),
    last_sync_id = EXCLUDED.last_sync_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
