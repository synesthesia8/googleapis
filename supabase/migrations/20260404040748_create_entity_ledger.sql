-- Replace policy_timeline with entity_ledger
-- Correct column order, correct name

-- Drop old functions first (they reference policy_timeline)
DROP FUNCTION IF EXISTS ads_v2.bootstrap_policy_timeline(text);
DROP FUNCTION IF EXISTS ads_v2.log_asset_in_ad_approval_change() CASCADE;
DROP FUNCTION IF EXISTS ads_v2.log_extension_approval_change() CASCADE;
DROP FUNCTION IF EXISTS ads_v2.log_ad_approval_change() CASCADE;

-- Drop old table
DROP TABLE IF EXISTS ads_v2.policy_timeline;

-- ═══════════════════════════════════════════════════════════════════
-- New table
-- ═══════════════════════════════════════════════════════════════════

CREATE TABLE ads_v2.entity_ledger (
  -- Identifiers
  id                    bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  customer_id           text NOT NULL,
  campaign_id           bigint,
  campaign_name         text,
  ad_group_id           bigint,
  ad_group_name         text,
  ad_id                 bigint,
  asset_id              bigint,

  -- What is it
  entity_type           text NOT NULL,
  asset_type            text,
  field_type            text,
  asset_content         text,

  -- What happened
  old_approval_status   text,
  new_approval_status   text,
  policy_topic_entries  jsonb,
  data                  jsonb,

  -- Metadata
  created_at            timestamptz NOT NULL DEFAULT now()
);

-- ═══════════════════════════════════════════════════════════════════
-- Indexes
-- ═══════════════════════════════════════════════════════════════════

CREATE INDEX idx_ledger_entity ON ads_v2.entity_ledger (entity_type, customer_id, asset_id, ad_id, field_type, created_at);
CREATE INDEX idx_ledger_time ON ads_v2.entity_ledger (created_at DESC);
CREATE INDEX idx_ledger_disapprovals ON ads_v2.entity_ledger (new_approval_status, created_at DESC)
  WHERE new_approval_status = 'DISAPPROVED';
CREATE INDEX idx_ledger_customer ON ads_v2.entity_ledger (customer_id, created_at DESC);

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

  SELECT COALESCE(
    a.data->'asset'->'textAsset'->>'text',
    a.data->'asset'->'sitelinkAsset'->>'linkText',
    a.data->'asset'->'calloutAsset'->>'calloutText',
    a.data->'asset'->'structuredSnippetAsset'->>'header',
    a.data->'asset'->>'name'
  ) INTO v_content
  FROM ads_v2.assets a
  WHERE a.asset_id = NEW.asset_id AND a.customer_id = NEW.customer_id;

  INSERT INTO ads_v2.entity_ledger (
    customer_id, campaign_id, campaign_name, ad_group_id, ad_group_name, ad_id, asset_id,
    entity_type, asset_type, field_type, asset_content,
    old_approval_status, new_approval_status, policy_topic_entries, data
  ) VALUES (
    NEW.customer_id,
    (NEW.data->'campaign'->>'id')::bigint,
    NEW.data->'campaign'->>'name',
    NEW.ad_group_id,
    NEW.data->'adGroup'->>'name',
    NEW.ad_id,
    NEW.asset_id,
    'ASSET_IN_AD',
    NEW.data->'asset'->>'type',
    NEW.field_type,
    v_content,
    v_old_status,
    v_new_status,
    NEW.data->'adGroupAdAssetView'->'policySummary'->'policyTopicEntries',
    NEW.data
  );

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_ledger_asset_in_ad
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

  INSERT INTO ads_v2.entity_ledger (
    customer_id, campaign_id, campaign_name, ad_group_id, ad_group_name, ad_id, asset_id,
    entity_type, asset_type, field_type, asset_content,
    old_approval_status, new_approval_status, policy_topic_entries, data
  ) VALUES (
    NEW.customer_id,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NEW.asset_id,
    'EXTENSION',
    NEW.data->'asset'->>'type',
    NEW.data->'asset'->'fieldTypePolicySummaries'->0->>'assetFieldType',
    COALESCE(
      NEW.data->'asset'->'sitelinkAsset'->>'linkText',
      NEW.data->'asset'->'calloutAsset'->>'calloutText',
      NEW.data->'asset'->'structuredSnippetAsset'->>'header',
      NEW.data->'asset'->>'name'
    ),
    v_old_status,
    v_new_status,
    NEW.data->'asset'->'policySummary'->'policyTopicEntries',
    NEW.data
  );

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_ledger_extension
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

  INSERT INTO ads_v2.entity_ledger (
    customer_id, campaign_id, campaign_name, ad_group_id, ad_group_name, ad_id, asset_id,
    entity_type, asset_type, field_type, asset_content,
    old_approval_status, new_approval_status, policy_topic_entries, data
  ) VALUES (
    NEW.customer_id,
    (NEW.data->'campaign'->>'id')::bigint,
    NEW.data->'campaign'->>'name',
    (NEW.data->'adGroup'->>'id')::bigint,
    NEW.data->'adGroup'->>'name',
    NEW.ad_id,
    NULL,
    'AD',
    NEW.data->'adGroupAd'->'ad'->>'type',
    NULL,
    NULL,
    v_old_status,
    v_new_status,
    NEW.data->'adGroupAd'->'policySummary'->'policyTopicEntries',
    NEW.data
  );

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_ledger_ad
  AFTER UPDATE ON ads_v2.ads
  FOR EACH ROW EXECUTE FUNCTION ads_v2.log_ad_approval_change();

-- ═══════════════════════════════════════════════════════════════════
-- Bootstrap
-- ═══════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION ads_v2.bootstrap_entity_ledger(p_customer_id text)
RETURNS void AS $$
BEGIN
  IF EXISTS (SELECT 1 FROM ads_v2.entity_ledger WHERE customer_id = p_customer_id) THEN
    RETURN;
  END IF;

  -- Bootstrap 1: All asset-in-ad rows
  INSERT INTO ads_v2.entity_ledger (
    customer_id, campaign_id, campaign_name, ad_group_id, ad_group_name, ad_id, asset_id,
    entity_type, asset_type, field_type, asset_content,
    old_approval_status, new_approval_status, policy_topic_entries, data
  )
  SELECT
    v.customer_id,
    (v.data->'campaign'->>'id')::bigint,
    v.data->'campaign'->>'name',
    v.ad_group_id,
    v.data->'adGroup'->>'name',
    v.ad_id,
    v.asset_id,
    'ASSET_IN_AD',
    v.data->'asset'->>'type',
    v.field_type,
    COALESCE(
      a.data->'asset'->'textAsset'->>'text',
      a.data->'asset'->'sitelinkAsset'->>'linkText',
      a.data->'asset'->'calloutAsset'->>'calloutText',
      a.data->'asset'->'structuredSnippetAsset'->>'header',
      a.data->'asset'->>'name'
    ),
    NULL,
    v.data->'adGroupAdAssetView'->'policySummary'->>'approvalStatus',
    v.data->'adGroupAdAssetView'->'policySummary'->'policyTopicEntries',
    v.data
  FROM ads_v2.ad_group_ad_asset_view v
  LEFT JOIN ads_v2.assets a ON a.asset_id = v.asset_id AND a.customer_id = v.customer_id
  WHERE v.customer_id = p_customer_id;

  -- Bootstrap 2: Extension assets with policySummary
  INSERT INTO ads_v2.entity_ledger (
    customer_id, campaign_id, campaign_name, ad_group_id, ad_group_name, ad_id, asset_id,
    entity_type, asset_type, field_type, asset_content,
    old_approval_status, new_approval_status, policy_topic_entries, data
  )
  SELECT
    a.customer_id,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    a.asset_id,
    'EXTENSION',
    a.data->'asset'->>'type',
    a.data->'asset'->'fieldTypePolicySummaries'->0->>'assetFieldType',
    COALESCE(
      a.data->'asset'->'sitelinkAsset'->>'linkText',
      a.data->'asset'->'calloutAsset'->>'calloutText',
      a.data->'asset'->'structuredSnippetAsset'->>'header',
      a.data->'asset'->>'name'
    ),
    NULL,
    a.data->'asset'->'policySummary'->>'approvalStatus',
    a.data->'asset'->'policySummary'->'policyTopicEntries',
    a.data
  FROM ads_v2.assets a
  WHERE a.customer_id = p_customer_id
    AND a.data->'asset'->'policySummary' IS NOT NULL;

  -- Bootstrap 3: All ads
  INSERT INTO ads_v2.entity_ledger (
    customer_id, campaign_id, campaign_name, ad_group_id, ad_group_name, ad_id, asset_id,
    entity_type, asset_type, field_type, asset_content,
    old_approval_status, new_approval_status, policy_topic_entries, data
  )
  SELECT
    ad.customer_id,
    (ad.data->'campaign'->>'id')::bigint,
    ad.data->'campaign'->>'name',
    (ad.data->'adGroup'->>'id')::bigint,
    ad.data->'adGroup'->>'name',
    ad.ad_id,
    NULL,
    'AD',
    ad.data->'adGroupAd'->'ad'->>'type',
    NULL,
    NULL,
    NULL,
    ad.data->'adGroupAd'->'policySummary'->>'approvalStatus',
    ad.data->'adGroupAd'->'policySummary'->'policyTopicEntries',
    ad.data
  FROM ads_v2.ads ad
  WHERE ad.customer_id = p_customer_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
