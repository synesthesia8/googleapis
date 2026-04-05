-- Approval log: append-only timeline of every approval status change
-- See: docs/decisions/0001-approval-log-design.md
-- See: docs/superpowers/specs/v2/2026-04-02-approval-log-spec.md

CREATE TABLE ads_v2.policy_timeline (
  id              bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  changed_at      timestamptz NOT NULL DEFAULT now(),

  entity_key      text NOT NULL,
  entity_type     text NOT NULL,
  customer_id     text NOT NULL,
  asset_id        bigint,
  ad_id           bigint,
  field_type      text,

  old_status      text,
  new_status      text,

  asset_content   text,
  asset_type      text,
  campaign_name   text,
  campaign_id     bigint,
  ad_group_name   text,
  ad_group_id     bigint,

  policy_topics   jsonb
);

CREATE INDEX idx_log_entity ON ads_v2.policy_timeline (entity_key, changed_at);
CREATE INDEX idx_log_time ON ads_v2.policy_timeline (changed_at DESC);
CREATE INDEX idx_log_disapprovals ON ads_v2.policy_timeline (new_status, changed_at DESC)
  WHERE new_status = 'DISAPPROVED';
CREATE INDEX idx_log_customer ON ads_v2.policy_timeline (customer_id, changed_at DESC);

-- ═══════════════════════════════════════════════════════════════════
-- Trigger 1: Asset-in-ad (ad_group_ad_asset_view)
-- ═══════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION ads_v2.log_asset_in_ad_approval_change()
RETURNS trigger AS $$
DECLARE
  v_old_status text;
  v_new_status text;
  v_content text;
BEGIN
  v_old_status := OLD.data->'adGroupAdAssetView'->'policySummary'->>'approvalStatus';
  v_new_status := NEW.data->'adGroupAdAssetView'->'policySummary'->>'approvalStatus';

  IF v_old_status IS NOT DISTINCT FROM v_new_status THEN
    RETURN NEW;
  END IF;

  -- Get asset content from assets table
  SELECT COALESCE(
    a.data->'asset'->'textAsset'->>'text',
    a.data->'asset'->'sitelinkAsset'->>'linkText',
    a.data->'asset'->'calloutAsset'->>'calloutText',
    a.data->'asset'->'structuredSnippetAsset'->>'header',
    a.data->'asset'->>'name'
  ) INTO v_content
  FROM ads_v2.assets a
  WHERE a.asset_id = NEW.asset_id AND a.customer_id = NEW.customer_id;

  INSERT INTO ads_v2.policy_timeline (
    entity_key, entity_type, customer_id, asset_id, ad_id, field_type,
    old_status, new_status, asset_content, asset_type,
    campaign_name, campaign_id, ad_group_name, ad_group_id, policy_topics
  ) VALUES (
    'ASSET_IN_AD:' || NEW.customer_id || ':' || NEW.asset_id || ':' || NEW.ad_id || ':' || NEW.field_type,
    'ASSET_IN_AD',
    NEW.customer_id,
    NEW.asset_id,
    NEW.ad_id,
    NEW.field_type,
    v_old_status,
    v_new_status,
    v_content,
    NEW.data->'asset'->>'type',
    NEW.data->'campaign'->>'name',
    (NEW.data->'campaign'->>'id')::bigint,
    NEW.data->'adGroup'->>'name',
    NEW.ad_group_id,
    NEW.data->'adGroupAdAssetView'->'policySummary'->'policyTopicEntries'
  );

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_log_asset_in_ad_approval
  AFTER UPDATE ON ads_v2.ad_group_ad_asset_view
  FOR EACH ROW EXECUTE FUNCTION ads_v2.log_asset_in_ad_approval_change();

-- ═══════════════════════════════════════════════════════════════════
-- Trigger 2: Extension asset (assets)
-- ═══════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION ads_v2.log_extension_approval_change()
RETURNS trigger AS $$
DECLARE
  v_old_status text;
  v_new_status text;
BEGIN
  v_old_status := OLD.data->'asset'->'policySummary'->>'approvalStatus';
  v_new_status := NEW.data->'asset'->'policySummary'->>'approvalStatus';

  IF v_old_status IS NOT DISTINCT FROM v_new_status THEN
    RETURN NEW;
  END IF;

  INSERT INTO ads_v2.policy_timeline (
    entity_key, entity_type, customer_id, asset_id, ad_id, field_type,
    old_status, new_status, asset_content, asset_type,
    campaign_name, campaign_id, ad_group_name, ad_group_id, policy_topics
  ) VALUES (
    'EXTENSION:' || NEW.customer_id || ':' || NEW.asset_id || '::',
    'EXTENSION',
    NEW.customer_id,
    NEW.asset_id,
    NULL,
    NEW.data->'asset'->'fieldTypePolicySummaries'->0->>'assetFieldType',
    v_old_status,
    v_new_status,
    COALESCE(
      NEW.data->'asset'->'sitelinkAsset'->>'linkText',
      NEW.data->'asset'->'calloutAsset'->>'calloutText',
      NEW.data->'asset'->'structuredSnippetAsset'->>'header',
      NEW.data->'asset'->>'name'
    ),
    NEW.data->'asset'->>'type',
    NULL,
    NULL,
    NULL,
    NULL,
    NEW.data->'asset'->'policySummary'->'policyTopicEntries'
  );

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_log_extension_approval
  AFTER UPDATE ON ads_v2.assets
  FOR EACH ROW EXECUTE FUNCTION ads_v2.log_extension_approval_change();

-- ═══════════════════════════════════════════════════════════════════
-- Trigger 3: Ad (ads)
-- ═══════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION ads_v2.log_ad_approval_change()
RETURNS trigger AS $$
DECLARE
  v_old_status text;
  v_new_status text;
BEGIN
  v_old_status := OLD.data->'adGroupAd'->'policySummary'->>'approvalStatus';
  v_new_status := NEW.data->'adGroupAd'->'policySummary'->>'approvalStatus';

  IF v_old_status IS NOT DISTINCT FROM v_new_status THEN
    RETURN NEW;
  END IF;

  INSERT INTO ads_v2.policy_timeline (
    entity_key, entity_type, customer_id, asset_id, ad_id, field_type,
    old_status, new_status, asset_content, asset_type,
    campaign_name, campaign_id, ad_group_name, ad_group_id, policy_topics
  ) VALUES (
    'AD:' || NEW.customer_id || '::' || NEW.ad_id || ':',
    'AD',
    NEW.customer_id,
    NULL,
    NEW.ad_id,
    NULL,
    v_old_status,
    v_new_status,
    NULL,
    NEW.data->'adGroupAd'->'ad'->>'type',
    NEW.data->'campaign'->>'name',
    (NEW.data->'campaign'->>'id')::bigint,
    NEW.data->'adGroup'->>'name',
    (NEW.data->'adGroup'->>'id')::bigint,
    NEW.data->'adGroupAd'->'policySummary'->'policyTopicEntries'
  );

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_log_ad_approval
  AFTER UPDATE ON ads_v2.ads
  FOR EACH ROW EXECUTE FUNCTION ads_v2.log_ad_approval_change();

-- ═══════════════════════════════════════════════════════════════════
-- Bootstrap function
-- ═══════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION ads_v2.bootstrap_policy_timeline(p_customer_id text)
RETURNS void AS $$
BEGIN
  -- Guard: only run once per customer
  IF EXISTS (SELECT 1 FROM ads_v2.policy_timeline WHERE customer_id = p_customer_id) THEN
    RETURN;
  END IF;

  -- Bootstrap 1: All asset-in-ad rows
  INSERT INTO ads_v2.policy_timeline (
    entity_key, entity_type, customer_id, asset_id, ad_id, field_type,
    old_status, new_status, asset_content, asset_type,
    campaign_name, campaign_id, ad_group_name, ad_group_id, policy_topics
  )
  SELECT
    'ASSET_IN_AD:' || v.customer_id || ':' || v.asset_id || ':' || v.ad_id || ':' || v.field_type,
    'ASSET_IN_AD',
    v.customer_id,
    v.asset_id,
    v.ad_id,
    v.field_type,
    NULL,
    v.data->'adGroupAdAssetView'->'policySummary'->>'approvalStatus',
    COALESCE(
      a.data->'asset'->'textAsset'->>'text',
      a.data->'asset'->'sitelinkAsset'->>'linkText',
      a.data->'asset'->'calloutAsset'->>'calloutText',
      a.data->'asset'->'structuredSnippetAsset'->>'header',
      a.data->'asset'->>'name'
    ),
    v.data->'asset'->>'type',
    v.data->'campaign'->>'name',
    (v.data->'campaign'->>'id')::bigint,
    v.data->'adGroup'->>'name',
    v.ad_group_id,
    v.data->'adGroupAdAssetView'->'policySummary'->'policyTopicEntries'
  FROM ads_v2.ad_group_ad_asset_view v
  LEFT JOIN ads_v2.assets a ON a.asset_id = v.asset_id AND a.customer_id = v.customer_id
  WHERE v.customer_id = p_customer_id;

  -- Bootstrap 2: Extension assets with policySummary
  INSERT INTO ads_v2.policy_timeline (
    entity_key, entity_type, customer_id, asset_id, ad_id, field_type,
    old_status, new_status, asset_content, asset_type,
    campaign_name, campaign_id, ad_group_name, ad_group_id, policy_topics
  )
  SELECT
    'EXTENSION:' || a.customer_id || ':' || a.asset_id || '::',
    'EXTENSION',
    a.customer_id,
    a.asset_id,
    NULL,
    a.data->'asset'->'fieldTypePolicySummaries'->0->>'assetFieldType',
    NULL,
    a.data->'asset'->'policySummary'->>'approvalStatus',
    COALESCE(
      a.data->'asset'->'sitelinkAsset'->>'linkText',
      a.data->'asset'->'calloutAsset'->>'calloutText',
      a.data->'asset'->'structuredSnippetAsset'->>'header',
      a.data->'asset'->>'name'
    ),
    a.data->'asset'->>'type',
    NULL,
    NULL,
    NULL,
    NULL,
    a.data->'asset'->'policySummary'->'policyTopicEntries'
  FROM ads_v2.assets a
  WHERE a.customer_id = p_customer_id
    AND a.data->'asset'->'policySummary' IS NOT NULL;

  -- Bootstrap 3: All ads
  INSERT INTO ads_v2.policy_timeline (
    entity_key, entity_type, customer_id, asset_id, ad_id, field_type,
    old_status, new_status, asset_content, asset_type,
    campaign_name, campaign_id, ad_group_name, ad_group_id, policy_topics
  )
  SELECT
    'AD:' || ad.customer_id || '::' || ad.ad_id || ':',
    'AD',
    ad.customer_id,
    NULL,
    ad.ad_id,
    NULL,
    NULL,
    ad.data->'adGroupAd'->'policySummary'->>'approvalStatus',
    NULL,
    ad.data->'adGroupAd'->'ad'->>'type',
    ad.data->'campaign'->>'name',
    (ad.data->'campaign'->>'id')::bigint,
    ad.data->'adGroup'->>'name',
    (ad.data->'adGroup'->>'id')::bigint,
    ad.data->'adGroupAd'->'policySummary'->'policyTopicEntries'
  FROM ads_v2.ads ad
  WHERE ad.customer_id = p_customer_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
