-- Realistic scenario: 1 account, 2 campaigns, multiple ads with mixed approval states

-- Account
INSERT INTO ads.accounts (customer_id, descriptive_name, currency_code, time_zone)
VALUES ('123-456-7890', 'My Test Account', 'AUD', 'Australia/Sydney');

-- Campaigns
INSERT INTO ads.campaigns (campaign_id, customer_id, name, status, serving_status, channel_type)
VALUES
  (100, '123-456-7890', 'Brand Campaign', 'ENABLED', 'SERVING', 'SEARCH'),
  (200, '123-456-7890', 'Competitor Campaign', 'ENABLED', 'SERVING', 'SEARCH');

-- Ad Groups
INSERT INTO ads.ad_groups (ad_group_id, customer_id, campaign_id, name, status)
VALUES
  (10, '123-456-7890', 100, 'Brand — Exact', 'ENABLED'),
  (20, '123-456-7890', 200, 'Competitor — Broad', 'ENABLED');

-- Ads
INSERT INTO ads.ads (ad_id, customer_id, ad_group_id, ad_type, status, approval_status, ad_strength)
VALUES
  (1001, '123-456-7890', 10, 'RESPONSIVE_SEARCH_AD', 'ENABLED', 'APPROVED', 'GOOD'),
  (1002, '123-456-7890', 10, 'RESPONSIVE_SEARCH_AD', 'ENABLED', 'DISAPPROVED', 'POOR'),
  (1003, '123-456-7890', 20, 'RESPONSIVE_SEARCH_AD', 'ENABLED', 'APPROVED', 'EXCELLENT');

-- Assets (the actual content)
INSERT INTO ads.assets (asset_id, customer_id, asset_type, text_content, global_approval)
VALUES
  (5001, '123-456-7890', 'TEXT', 'Official Brand Store', 'APPROVED'),
  (5002, '123-456-7890', 'TEXT', 'Buy Cheap Meds Now', 'DISAPPROVED'),
  (5003, '123-456-7890', 'TEXT', 'Best Prices Guaranteed', 'APPROVED'),
  (5004, '123-456-7890', 'TEXT', 'Free Shipping Today', 'APPROVED'),
  (5005, '123-456-7890', 'TEXT', 'Limited Time Offer', 'APPROVED_LIMITED');

-- Asset Links — Ad level (headlines in RSAs)
INSERT INTO ads.asset_links (customer_id, link_level, asset_id, field_type, campaign_id, ad_group_id, ad_id, approval_status, link_status, last_checked_at)
VALUES
  -- Ad 1001 (approved ad, all headlines fine)
  ('123-456-7890', 'AD', 5001, 'HEADLINE', 100, 10, 1001, 'APPROVED', 'ENABLED', now()),
  ('123-456-7890', 'AD', 5003, 'HEADLINE', 100, 10, 1001, 'APPROVED', 'ENABLED', now()),
  ('123-456-7890', 'AD', 5004, 'HEADLINE', 100, 10, 1001, 'APPROVED', 'ENABLED', now()),

  -- Ad 1002 (disapproved ad, one bad headline)
  ('123-456-7890', 'AD', 5002, 'HEADLINE', 100, 10, 1002, 'DISAPPROVED', 'ENABLED', now()),
  ('123-456-7890', 'AD', 5003, 'HEADLINE', 100, 10, 1002, 'APPROVED', 'ENABLED', now()),

  -- Ad 1003 (approved ad, one limited headline)
  ('123-456-7890', 'AD', 5005, 'HEADLINE', 200, 20, 1003, 'APPROVED_LIMITED', 'ENABLED', now()),
  ('123-456-7890', 'AD', 5004, 'HEADLINE', 200, 20, 1003, 'APPROVED', 'ENABLED', now());

-- Asset Links — Account level (sitelink disapproved)
INSERT INTO ads.assets (asset_id, customer_id, asset_type, sitelink_text, sitelink_desc1, global_approval)
VALUES (5006, '123-456-7890', 'SITELINK', 'Free Trial', 'Start your free trial today', 'DISAPPROVED');

INSERT INTO ads.asset_links (customer_id, link_level, asset_id, field_type, approval_status, link_status, last_checked_at)
VALUES ('123-456-7890', 'CUSTOMER', 5006, 'SITELINK', 'DISAPPROVED', 'ENABLED', now());

-- Refresh the cascade view
REFRESH MATERIALIZED VIEW ads.cascade_status;
