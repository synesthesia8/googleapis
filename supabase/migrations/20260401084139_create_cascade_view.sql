CREATE MATERIALIZED VIEW ads.cascade_status AS
SELECT
  al.id               AS asset_link_id,
  al.customer_id,
  al.link_level,
  al.asset_id,
  al.field_type,

  -- The asset itself
  a.asset_type,
  a.text_content,
  a.image_url,
  a.sitelink_text,
  a.callout_text,
  a.youtube_video_id,
  a.phone_number,
  al.approval_status   AS asset_link_approval,
  al.review_status     AS asset_link_review,
  al.primary_status,
  al.policy_topics,
  a.global_approval    AS asset_global_approval,

  -- The ad (null for non-AD link levels)
  ad.ad_id,
  ad.ad_type,
  ad.status            AS ad_status,
  ad.approval_status   AS ad_approval,
  ad.ad_strength,

  -- The ad group
  ag.ad_group_id,
  ag.name              AS ad_group_name,
  ag.status            AS ad_group_status,

  -- The campaign
  c.campaign_id,
  c.name               AS campaign_name,
  c.status             AS campaign_status,
  c.serving_status     AS campaign_serving,
  c.channel_type,

  -- Impact assessment
  CASE
    WHEN al.approval_status = 'DISAPPROVED'
      AND ad.approval_status = 'DISAPPROVED' THEN 'AD_KILLED'
    WHEN al.approval_status = 'DISAPPROVED'
      AND (ad.approval_status IS NULL OR ad.approval_status != 'DISAPPROVED') THEN 'ASSET_ONLY'
    WHEN al.approval_status = 'APPROVED_LIMITED' THEN 'LIMITED_REACH'
    WHEN al.approval_status = 'AREA_OF_INTEREST_ONLY' THEN 'GEO_RESTRICTED'
    ELSE 'OTHER'
  END AS impact_level,

  -- Freshness
  CASE
    WHEN al.last_checked_at > now() - interval '2 hours' THEN 'FRESH'
    WHEN al.last_checked_at > now() - interval '6 hours' THEN 'STALE'
    ELSE 'UNKNOWN'
  END AS freshness,

  al.last_checked_at

FROM ads.asset_links al
JOIN ads.assets a
  ON al.asset_id = a.asset_id AND al.customer_id = a.customer_id
LEFT JOIN ads.ads ad
  ON al.ad_id = ad.ad_id AND al.customer_id = ad.customer_id
LEFT JOIN ads.ad_groups ag
  ON al.ad_group_id = ag.ad_group_id AND al.customer_id = ag.customer_id
LEFT JOIN ads.campaigns c
  ON al.campaign_id = c.campaign_id AND al.customer_id = c.customer_id
WHERE al.approval_status != 'APPROVED'
  AND (al.link_status IS NULL OR al.link_status != 'REMOVED');

-- Unique index required for REFRESH CONCURRENTLY
CREATE UNIQUE INDEX idx_cascade_status_pk ON ads.cascade_status (asset_link_id);
CREATE INDEX idx_cascade_status_customer ON ads.cascade_status (customer_id);
CREATE INDEX idx_cascade_status_impact ON ads.cascade_status (impact_level);
