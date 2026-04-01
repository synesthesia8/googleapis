CREATE OR REPLACE FUNCTION ads.upsert_asset_links(
  p_customer_id text,
  p_sync_id text,
  p_rows jsonb
) RETURNS void AS $$
BEGIN
  INSERT INTO ads.asset_links (
    customer_id, link_level, asset_id, field_type,
    campaign_id, ad_group_id, ad_id,
    link_status, approval_status, review_status,
    primary_status, primary_status_reasons, policy_topics,
    is_enabled, performance_label, pinned_field, asset_source,
    last_sync_id, last_checked_at
  )
  SELECT
    p_customer_id,
    r->>'linkLevel',
    (r->>'assetId')::bigint,
    r->>'fieldType',
    (r->>'campaignId')::bigint,
    (r->>'adGroupId')::bigint,
    (r->>'adId')::bigint,
    r->>'linkStatus',
    r->>'approvalStatus',
    r->>'reviewStatus',
    r->>'primaryStatus',
    CASE WHEN jsonb_typeof(r->'primaryStatusReasons') = 'array'
      THEN ARRAY(SELECT jsonb_array_elements_text(r->'primaryStatusReasons'))
      ELSE NULL
    END,
    CASE WHEN jsonb_typeof(r->'policyTopics') IN ('array', 'object')
      THEN r->'policyTopics'
      ELSE NULL
    END,
    (r->>'isEnabled')::boolean,
    r->>'performanceLabel',
    r->>'pinnedField',
    r->>'assetSource',
    p_sync_id::uuid,
    now()
  FROM jsonb_array_elements(p_rows) AS r
  ON CONFLICT (customer_id, link_level, asset_id, field_type,
               COALESCE(campaign_id, 0), COALESCE(ad_group_id, 0), COALESCE(ad_id, 0))
  DO UPDATE SET
    link_status = EXCLUDED.link_status,
    approval_status = EXCLUDED.approval_status,
    review_status = EXCLUDED.review_status,
    primary_status = EXCLUDED.primary_status,
    primary_status_reasons = EXCLUDED.primary_status_reasons,
    policy_topics = EXCLUDED.policy_topics,
    is_enabled = EXCLUDED.is_enabled,
    performance_label = EXCLUDED.performance_label,
    pinned_field = EXCLUDED.pinned_field,
    asset_source = EXCLUDED.asset_source,
    last_sync_id = EXCLUDED.last_sync_id,
    last_checked_at = now();
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
