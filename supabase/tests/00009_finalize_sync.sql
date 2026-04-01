BEGIN;
SELECT plan(3);

-- Seed full hierarchy
INSERT INTO ads.accounts (customer_id) VALUES ('test-cid');
SELECT ads.upsert_campaigns('test-cid', 'a0000000-0000-0000-0000-000000000001', '[{"campaignId": 1, "name": "C1", "status": "ENABLED", "servingStatus": "SERVING", "channelType": "SEARCH"}]'::jsonb);
SELECT ads.upsert_ad_groups('test-cid', 'a0000000-0000-0000-0000-000000000001', '[{"adGroupId": 1, "campaignId": 1, "name": "AG1", "status": "ENABLED"}]'::jsonb);
SELECT ads.upsert_ads('test-cid', 'a0000000-0000-0000-0000-000000000001', '[{"adId": 1, "adGroupId": 1, "adType": "RESPONSIVE_SEARCH_AD", "status": "ENABLED", "approvalStatus": "APPROVED"}]'::jsonb);
SELECT ads.upsert_assets('test-cid', 'a0000000-0000-0000-0000-000000000001', '[{"assetId": 1, "assetType": "TEXT", "textContent": "Hello", "globalApproval": "APPROVED"}]'::jsonb);
SELECT ads.upsert_asset_links('test-cid', 'a0000000-0000-0000-0000-000000000001', '[{"linkLevel": "AD", "assetId": 1, "fieldType": "HEADLINE", "campaignId": 1, "adGroupId": 1, "adId": 1, "approvalStatus": "APPROVED", "linkStatus": "ENABLED"}]'::jsonb);

-- Create sync run for sync 1
INSERT INTO ads.sync_runs (id, customer_id, is_first_sync) VALUES ('a0000000-0000-0000-0000-000000000001', 'test-cid', true);

-- Sync 2: asset_link not included (simulates removal from Google Ads)
INSERT INTO ads.sync_runs (id, customer_id) VALUES ('a0000000-0000-0000-0000-000000000002', 'test-cid');

-- Finalize sync 2
SELECT ads.finalize_sync('test-cid', 'a0000000-0000-0000-0000-000000000002');

-- Test 1: Missing asset_link should be marked REMOVED
SELECT is(
  (SELECT link_status FROM ads.asset_links WHERE customer_id = 'test-cid' LIMIT 1),
  'REMOVED',
  'Asset link not seen in sync should be marked REMOVED'
);

-- Test 2: status_change should be logged for the removal
SELECT is(
  (SELECT count(*)::int FROM ads.status_changes WHERE field_name = 'link_status' AND new_value = 'REMOVED'),
  1,
  'Removal should be logged in status_changes'
);

-- Test 3: sync_run should be marked completed
SELECT is(
  (SELECT status FROM ads.sync_runs WHERE id = 'a0000000-0000-0000-0000-000000000002'),
  'completed',
  'Sync run should be marked completed'
);

SELECT * FROM finish();
ROLLBACK;
