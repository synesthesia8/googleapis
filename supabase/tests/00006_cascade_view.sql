BEGIN;
SELECT plan(5);

-- Seed: full hierarchy with one disapproved asset
INSERT INTO ads.accounts (customer_id, descriptive_name) VALUES ('test-cid', 'Test Account');
INSERT INTO ads.campaigns (campaign_id, customer_id, name, status, serving_status, channel_type)
  VALUES (1, 'test-cid', 'Brand Campaign', 'ENABLED', 'SERVING', 'SEARCH');
INSERT INTO ads.ad_groups (ad_group_id, customer_id, campaign_id, name, status)
  VALUES (1, 'test-cid', 1, 'Brand Terms', 'ENABLED');
INSERT INTO ads.ads (ad_id, customer_id, ad_group_id, ad_type, status, approval_status)
  VALUES (1, 'test-cid', 1, 'RESPONSIVE_SEARCH_AD', 'ENABLED', 'DISAPPROVED');
INSERT INTO ads.assets (asset_id, customer_id, asset_type, text_content, global_approval)
  VALUES (1, 'test-cid', 'TEXT', 'Buy cheap meds now', 'DISAPPROVED');
INSERT INTO ads.asset_links (customer_id, link_level, asset_id, field_type, campaign_id, ad_group_id, ad_id, approval_status, link_status, last_checked_at)
  VALUES ('test-cid', 'AD', 1, 'HEADLINE', 1, 1, 1, 'DISAPPROVED', 'ENABLED', now());

-- Also insert an APPROVED asset link (different asset, same ad)
INSERT INTO ads.assets (asset_id, customer_id, asset_type, text_content, global_approval)
  VALUES (2, 'test-cid', 'TEXT', 'Great deals here', 'APPROVED');
INSERT INTO ads.asset_links (customer_id, link_level, asset_id, field_type, campaign_id, ad_group_id, ad_id, approval_status, link_status, last_checked_at)
  VALUES ('test-cid', 'AD', 2, 'HEADLINE', 1, 1, 1, 'APPROVED', 'ENABLED', now());

-- Refresh the materialized view
REFRESH MATERIALIZED VIEW ads.cascade_status;

-- Test 1: View should have exactly 1 row for test-cid (only non-approved)
SELECT is(
  (SELECT count(*)::int FROM ads.cascade_status WHERE customer_id = 'test-cid'),
  1,
  'Cascade view should only show non-approved asset links for test customer'
);

-- Test 2: Should show the correct asset content
SELECT is(
  (SELECT text_content FROM ads.cascade_status WHERE customer_id = 'test-cid' LIMIT 1),
  'Buy cheap meds now',
  'Should show the asset text content'
);

-- Test 3: Should show ad is DISAPPROVED
SELECT is(
  (SELECT ad_approval FROM ads.cascade_status WHERE customer_id = 'test-cid' LIMIT 1),
  'DISAPPROVED',
  'Should show ad approval status'
);

-- Test 4: Should show campaign is still SERVING
SELECT is(
  (SELECT campaign_serving FROM ads.cascade_status WHERE customer_id = 'test-cid' LIMIT 1),
  'SERVING',
  'Should show campaign serving status'
);

-- Test 5: Impact level should be AD_KILLED (ad is disapproved)
SELECT is(
  (SELECT impact_level FROM ads.cascade_status WHERE customer_id = 'test-cid' LIMIT 1),
  'AD_KILLED',
  'Impact level should be AD_KILLED when ad is disapproved'
);

SELECT * FROM finish();
ROLLBACK;
