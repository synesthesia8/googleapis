BEGIN;
SELECT plan(15);

-- Seed test data
INSERT INTO ads.accounts (customer_id, descriptive_name) VALUES ('test-cid', 'Test Account');
INSERT INTO ads.campaigns (campaign_id, customer_id, name, status, serving_status)
  VALUES (1, 'test-cid', 'Test Campaign', 'ENABLED', 'SERVING');
INSERT INTO ads.ad_groups (ad_group_id, customer_id, campaign_id, name, status)
  VALUES (1, 'test-cid', 1, 'Test Ad Group', 'ENABLED');
INSERT INTO ads.ads (ad_id, customer_id, ad_group_id, status, approval_status, review_status)
  VALUES (1, 'test-cid', 1, 'ENABLED', 'APPROVED', 'REVIEWED');
INSERT INTO ads.assets (asset_id, customer_id, asset_type, text_content, global_approval)
  VALUES (1, 'test-cid', 'TEXT', 'Test headline', 'APPROVED');
INSERT INTO ads.asset_links (customer_id, link_level, asset_id, field_type, campaign_id, ad_group_id, ad_id, approval_status, review_status, primary_status, link_status)
  VALUES ('test-cid', 'AD', 1, 'HEADLINE', 1, 1, 1, 'APPROVED', 'REVIEWED', 'ELIGIBLE', 'ENABLED');

-- Test 1: No changes logged yet
SELECT is(
  (SELECT count(*)::int FROM ads.status_changes),
  0,
  'No status changes before any updates'
);

-- ── ASSET LINK: 4 tracked fields ────────────────────────────

-- Test 2: approval_status
UPDATE ads.asset_links SET approval_status = 'DISAPPROVED' WHERE id = 1;
SELECT is(
  (SELECT count(*)::int FROM ads.status_changes WHERE entity_type = 'ASSET_LINK' AND field_name = 'approval_status'),
  1,
  'asset_link approval_status change logged'
);

-- Test 3: review_status
UPDATE ads.asset_links SET review_status = 'UNDER_APPEAL' WHERE id = 1;
SELECT is(
  (SELECT count(*)::int FROM ads.status_changes WHERE entity_type = 'ASSET_LINK' AND field_name = 'review_status'),
  1,
  'asset_link review_status change logged'
);

-- Test 4: primary_status
UPDATE ads.asset_links SET primary_status = 'NOT_ELIGIBLE' WHERE id = 1;
SELECT is(
  (SELECT count(*)::int FROM ads.status_changes WHERE entity_type = 'ASSET_LINK' AND field_name = 'primary_status'),
  1,
  'asset_link primary_status change logged'
);

-- Test 5: link_status
UPDATE ads.asset_links SET link_status = 'PAUSED' WHERE id = 1;
SELECT is(
  (SELECT count(*)::int FROM ads.status_changes WHERE entity_type = 'ASSET_LINK' AND field_name = 'link_status'),
  1,
  'asset_link link_status change logged'
);

-- Test 6: non-tracked field does NOT trigger
UPDATE ads.asset_links SET performance_label = 'BEST' WHERE id = 1;
SELECT is(
  (SELECT count(*)::int FROM ads.status_changes WHERE entity_type = 'ASSET_LINK'),
  4,
  'asset_link non-tracked field update does not log'
);

-- ── AD: 3 tracked fields ────────────────────────────────────

-- Test 7: approval_status
UPDATE ads.ads SET approval_status = 'DISAPPROVED' WHERE ad_id = 1 AND customer_id = 'test-cid';
SELECT is(
  (SELECT count(*)::int FROM ads.status_changes WHERE entity_type = 'AD' AND field_name = 'approval_status'),
  1,
  'ad approval_status change logged'
);

-- Test 8: review_status
UPDATE ads.ads SET review_status = 'REVIEW_IN_PROGRESS' WHERE ad_id = 1 AND customer_id = 'test-cid';
SELECT is(
  (SELECT count(*)::int FROM ads.status_changes WHERE entity_type = 'AD' AND field_name = 'review_status'),
  1,
  'ad review_status change logged'
);

-- Test 9: status
UPDATE ads.ads SET status = 'PAUSED' WHERE ad_id = 1 AND customer_id = 'test-cid';
SELECT is(
  (SELECT count(*)::int FROM ads.status_changes WHERE entity_type = 'AD' AND field_name = 'status'),
  1,
  'ad status change logged'
);

-- ── AD GROUP: 1 tracked field ───────────────────────────────

-- Test 10: status
UPDATE ads.ad_groups SET status = 'PAUSED' WHERE ad_group_id = 1 AND customer_id = 'test-cid';
SELECT is(
  (SELECT count(*)::int FROM ads.status_changes WHERE entity_type = 'AD_GROUP' AND field_name = 'status'),
  1,
  'ad_group status change logged'
);

-- ── CAMPAIGN: 2 tracked fields ──────────────────────────────

-- Test 11: status
UPDATE ads.campaigns SET status = 'PAUSED' WHERE campaign_id = 1 AND customer_id = 'test-cid';
SELECT is(
  (SELECT count(*)::int FROM ads.status_changes WHERE entity_type = 'CAMPAIGN' AND field_name = 'status'),
  1,
  'campaign status change logged'
);

-- Test 12: serving_status
UPDATE ads.campaigns SET serving_status = 'NONE' WHERE campaign_id = 1 AND customer_id = 'test-cid';
SELECT is(
  (SELECT count(*)::int FROM ads.status_changes WHERE entity_type = 'CAMPAIGN' AND field_name = 'serving_status'),
  1,
  'campaign serving_status change logged'
);

-- ── VERIFY old_value / new_value correctness ────────────────

-- Test 13: old_value captured correctly
SELECT is(
  (SELECT old_value FROM ads.status_changes WHERE entity_type = 'ASSET_LINK' AND field_name = 'approval_status' LIMIT 1),
  'APPROVED',
  'old_value should be APPROVED for asset_link approval change'
);

-- Test 14: new_value captured correctly
SELECT is(
  (SELECT new_value FROM ads.status_changes WHERE entity_type = 'ASSET_LINK' AND field_name = 'approval_status' LIMIT 1),
  'DISAPPROVED',
  'new_value should be DISAPPROVED for asset_link approval change'
);

-- ── VERIFY updated_at auto-updates ──────────────────────────

-- Test 15: updated_at should be recent (within last 5 seconds)
SELECT ok(
  (SELECT updated_at > now() - interval '5 seconds' FROM ads.asset_links WHERE id = 1),
  'updated_at should be auto-updated on change'
);

SELECT * FROM finish();
ROLLBACK;
