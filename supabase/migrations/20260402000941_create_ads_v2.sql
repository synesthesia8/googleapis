CREATE SCHEMA IF NOT EXISTS ads_v2;

GRANT USAGE ON SCHEMA ads_v2 TO postgres, anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA ads_v2 GRANT ALL ON TABLES TO postgres, service_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA ads_v2 GRANT SELECT ON TABLES TO anon, authenticated;
ALTER DEFAULT PRIVILEGES IN SCHEMA ads_v2 GRANT EXECUTE ON FUNCTIONS TO postgres, service_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA ads_v2 GRANT EXECUTE ON FUNCTIONS TO anon, authenticated;

CREATE TABLE ads_v2.accounts (
  customer_id     text PRIMARY KEY,
  data            jsonb NOT NULL,
  last_sync_id    uuid,
  last_checked_at timestamptz,
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE ads_v2.campaigns (
  campaign_id     bigint NOT NULL,
  customer_id     text NOT NULL,
  data            jsonb NOT NULL,
  last_sync_id    uuid,
  last_checked_at timestamptz,
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (campaign_id, customer_id)
);

CREATE TABLE ads_v2.ad_groups (
  ad_group_id     bigint NOT NULL,
  customer_id     text NOT NULL,
  data            jsonb NOT NULL,
  last_sync_id    uuid,
  last_checked_at timestamptz,
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (ad_group_id, customer_id)
);

CREATE TABLE ads_v2.ads (
  ad_id           bigint NOT NULL,
  customer_id     text NOT NULL,
  data            jsonb NOT NULL,
  last_sync_id    uuid,
  last_checked_at timestamptz,
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (ad_id, customer_id)
);

CREATE TABLE ads_v2.assets (
  asset_id        bigint NOT NULL,
  customer_id     text NOT NULL,
  data            jsonb NOT NULL,
  last_sync_id    uuid,
  last_checked_at timestamptz,
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (asset_id, customer_id)
);

CREATE TABLE ads_v2.customer_assets (
  customer_id     text NOT NULL,
  asset_id        bigint NOT NULL,
  field_type      text NOT NULL,
  data            jsonb NOT NULL,
  last_sync_id    uuid,
  last_checked_at timestamptz,
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (customer_id, asset_id, field_type)
);

CREATE TABLE ads_v2.campaign_assets (
  customer_id     text NOT NULL,
  campaign_id     bigint NOT NULL,
  asset_id        bigint NOT NULL,
  field_type      text NOT NULL,
  data            jsonb NOT NULL,
  last_sync_id    uuid,
  last_checked_at timestamptz,
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (customer_id, campaign_id, asset_id, field_type)
);

CREATE TABLE ads_v2.ad_group_assets (
  customer_id     text NOT NULL,
  ad_group_id     bigint NOT NULL,
  asset_id        bigint NOT NULL,
  field_type      text NOT NULL,
  data            jsonb NOT NULL,
  last_sync_id    uuid,
  last_checked_at timestamptz,
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (customer_id, ad_group_id, asset_id, field_type)
);

CREATE TABLE ads_v2.ad_group_ad_asset_view (
  customer_id     text NOT NULL,
  ad_group_id     bigint NOT NULL,
  ad_id           bigint NOT NULL,
  asset_id        bigint NOT NULL,
  field_type      text NOT NULL,
  data            jsonb NOT NULL,
  last_sync_id    uuid,
  last_checked_at timestamptz,
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (customer_id, ad_group_id, ad_id, asset_id, field_type)
);

CREATE TABLE ads_v2.sync_runs (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  customer_id     text NOT NULL,
  started_at      timestamptz NOT NULL DEFAULT now(),
  completed_at    timestamptz,
  status          text NOT NULL DEFAULT 'running',
  rows_by_type    jsonb,
  truncation_warnings text[],
  error           text,
  CONSTRAINT valid_sync_status CHECK (status IN ('running', 'completed', 'failed'))
);
