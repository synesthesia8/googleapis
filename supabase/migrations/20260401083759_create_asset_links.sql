CREATE TABLE ads.asset_links (
  id                  bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  customer_id         text NOT NULL,
  link_level          text NOT NULL,
  asset_id            bigint NOT NULL,
  field_type          text NOT NULL,
  campaign_id         bigint,
  ad_group_id         bigint,
  ad_id               bigint,
  link_status         text,
  approval_status     text NOT NULL,
  review_status       text,
  primary_status      text,
  primary_status_reasons text[],
  policy_topics       jsonb,
  is_enabled          boolean,
  performance_label   text,
  pinned_field        text,
  asset_source        text,
  last_sync_id        uuid,
  last_checked_at     timestamptz,
  first_seen_at       timestamptz NOT NULL DEFAULT now(),
  updated_at          timestamptz NOT NULL DEFAULT now(),

  CONSTRAINT valid_link_level CHECK (link_level IN ('CUSTOMER', 'CAMPAIGN', 'AD_GROUP', 'AD'))
);

CREATE UNIQUE INDEX idx_asset_links_natural_key
  ON ads.asset_links (
    customer_id, link_level, asset_id, field_type,
    COALESCE(campaign_id, 0), COALESCE(ad_group_id, 0), COALESCE(ad_id, 0)
  );

CREATE INDEX idx_asset_links_disapproved
  ON ads.asset_links (customer_id, approval_status)
  WHERE approval_status != 'APPROVED';

CREATE INDEX idx_asset_links_hierarchy
  ON ads.asset_links (customer_id, campaign_id, ad_group_id, ad_id);

CREATE INDEX idx_asset_links_asset
  ON ads.asset_links (customer_id, asset_id);

CREATE INDEX idx_asset_links_sync
  ON ads.asset_links (customer_id, last_sync_id);
