-- Fix: use jsonb_typeof() guards to prevent "cannot extract elements from a scalar" errors
-- when Google Ads returns null/string instead of array/object for policy fields

-- ── upsert_assets ────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION ads.upsert_assets(
  p_customer_id text,
  p_sync_id text,
  p_rows jsonb
) RETURNS void AS $$
BEGIN
  INSERT INTO ads.assets (
    asset_id, customer_id, name, asset_type,
    text_content, image_url, image_width, image_height,
    youtube_video_id, sitelink_text, sitelink_desc1, sitelink_desc2,
    callout_text, snippet_header, snippet_values, phone_number,
    global_approval, global_review, global_policy_topics,
    last_checked_at, last_sync_id
  )
  SELECT
    (r->>'assetId')::bigint,
    p_customer_id,
    r->>'name',
    r->>'assetType',
    r->>'textContent',
    r->>'imageUrl',
    (r->>'imageWidth')::int,
    (r->>'imageHeight')::int,
    r->>'youtubeVideoId',
    r->>'sitelinkText',
    r->>'sitelinkDesc1',
    r->>'sitelinkDesc2',
    r->>'calloutText',
    r->>'snippetHeader',
    CASE WHEN jsonb_typeof(r->'snippetValues') = 'array'
      THEN ARRAY(SELECT jsonb_array_elements_text(r->'snippetValues'))
      ELSE NULL
    END,
    r->>'phoneNumber',
    r->>'globalApproval',
    r->>'globalReview',
    CASE WHEN jsonb_typeof(r->'globalPolicyTopics') IN ('array', 'object')
      THEN r->'globalPolicyTopics'
      ELSE NULL
    END,
    now(),
    p_sync_id::uuid
  FROM jsonb_array_elements(p_rows) AS r
  ON CONFLICT (asset_id, customer_id)
  DO UPDATE SET
    name = EXCLUDED.name,
    asset_type = EXCLUDED.asset_type,
    text_content = EXCLUDED.text_content,
    image_url = EXCLUDED.image_url,
    image_width = EXCLUDED.image_width,
    image_height = EXCLUDED.image_height,
    youtube_video_id = EXCLUDED.youtube_video_id,
    sitelink_text = EXCLUDED.sitelink_text,
    sitelink_desc1 = EXCLUDED.sitelink_desc1,
    sitelink_desc2 = EXCLUDED.sitelink_desc2,
    callout_text = EXCLUDED.callout_text,
    snippet_header = EXCLUDED.snippet_header,
    snippet_values = EXCLUDED.snippet_values,
    phone_number = EXCLUDED.phone_number,
    global_approval = EXCLUDED.global_approval,
    global_review = EXCLUDED.global_review,
    global_policy_topics = EXCLUDED.global_policy_topics,
    last_checked_at = now(),
    last_sync_id = EXCLUDED.last_sync_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ── upsert_ads ───────────────────────────────────────────────────────────────
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
    CASE WHEN jsonb_typeof(r->'policyTopics') IN ('array', 'object')
      THEN r->'policyTopics'
      ELSE NULL
    END,
    CASE WHEN jsonb_typeof(r->'finalUrls') = 'array'
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

-- ── upsert_asset_links ───────────────────────────────────────────────────────
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
