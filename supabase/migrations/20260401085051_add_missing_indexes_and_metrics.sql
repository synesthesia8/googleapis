-- Missing indexes from spec
CREATE INDEX idx_ads_approval
  ON ads.ads (customer_id, approval_status)
  WHERE approval_status != 'APPROVED';

CREATE INDEX idx_campaigns_serving
  ON ads.campaigns (customer_id, serving_status);

CREATE INDEX idx_campaigns_freshness
  ON ads.campaigns (customer_id, last_checked_at);

CREATE INDEX idx_asset_links_freshness
  ON ads.asset_links (customer_id, last_checked_at);

-- Metrics table (separate from status data, never diffed)
CREATE TABLE ads.metrics_daily (
  customer_id         text NOT NULL,
  entity_type         text NOT NULL,
  entity_id           bigint NOT NULL,
  date                date NOT NULL,
  impressions         bigint,
  clicks              bigint,
  cost_micros         bigint,
  conversions         numeric,
  conversions_value   numeric,
  ctr                 numeric,
  avg_cpc             numeric,
  PRIMARY KEY (customer_id, entity_type, entity_id, date),

  CONSTRAINT valid_metric_entity_type CHECK (entity_type IN ('CAMPAIGN', 'AD_GROUP', 'AD'))
);
