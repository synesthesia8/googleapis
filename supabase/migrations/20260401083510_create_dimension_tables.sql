CREATE TABLE ads.accounts (
  customer_id       text PRIMARY KEY,
  descriptive_name  text,
  currency_code     text,
  time_zone         text,
  is_mcc            boolean,
  mcc_customer_id   text,
  status            text,
  created_at        timestamptz NOT NULL DEFAULT now(),
  updated_at        timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE ads.campaigns (
  campaign_id         bigint NOT NULL,
  customer_id         text NOT NULL REFERENCES ads.accounts(customer_id),
  name                text,
  status              text,
  serving_status      text,
  channel_type        text,
  channel_sub_type    text,
  bidding_strategy    text,
  start_date          date,
  end_date            date,
  budget_amount_micros bigint,
  last_checked_at     timestamptz,
  last_sync_id        uuid,
  created_at          timestamptz NOT NULL DEFAULT now(),
  updated_at          timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (campaign_id, customer_id)
);

CREATE TABLE ads.ad_groups (
  ad_group_id       bigint NOT NULL,
  customer_id       text NOT NULL,
  campaign_id       bigint NOT NULL,
  name              text,
  status            text,
  type              text,
  cpc_bid_micros    bigint,
  last_checked_at   timestamptz,
  last_sync_id      uuid,
  created_at        timestamptz NOT NULL DEFAULT now(),
  updated_at        timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (ad_group_id, customer_id),
  FOREIGN KEY (campaign_id, customer_id) REFERENCES ads.campaigns(campaign_id, customer_id)
);

CREATE TABLE ads.ads (
  ad_id             bigint NOT NULL,
  customer_id       text NOT NULL,
  ad_group_id       bigint NOT NULL,
  ad_type           text,
  status            text,
  approval_status   text,
  review_status     text,
  ad_strength       text,
  policy_topics     jsonb,
  final_urls        text[],
  last_checked_at   timestamptz,
  last_sync_id      uuid,
  created_at        timestamptz NOT NULL DEFAULT now(),
  updated_at        timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (ad_id, customer_id),
  FOREIGN KEY (ad_group_id, customer_id) REFERENCES ads.ad_groups(ad_group_id, customer_id)
);

CREATE TABLE ads.assets (
  asset_id            bigint NOT NULL,
  customer_id         text NOT NULL,
  name                text,
  asset_type          text NOT NULL,
  text_content        text,
  image_url           text,
  image_width         int,
  image_height        int,
  youtube_video_id    text,
  sitelink_text       text,
  sitelink_desc1      text,
  sitelink_desc2      text,
  callout_text        text,
  snippet_header      text,
  snippet_values      text[],
  phone_number        text,
  global_approval     text,
  global_review       text,
  global_policy_topics jsonb,
  last_checked_at     timestamptz,
  last_sync_id        uuid,
  created_at          timestamptz NOT NULL DEFAULT now(),
  updated_at          timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (asset_id, customer_id)
);
