BEGIN;
SELECT plan(5);

-- Seed
INSERT INTO ads.accounts (customer_id, descriptive_name) VALUES ('test-cid', 'Test');

-- Test upsert_campaigns
SELECT ads.upsert_campaigns('test-cid', 'a0000000-0000-0000-0000-000000000001', '[{"campaignId": 1, "name": "C1", "status": "ENABLED", "servingStatus": "SERVING", "channelType": "SEARCH"}]'::jsonb);
SELECT is((SELECT count(*)::int FROM ads.campaigns WHERE customer_id = 'test-cid'), 1, 'upsert_campaigns works');

-- Test upsert_ad_groups
SELECT ads.upsert_ad_groups('test-cid', 'a0000000-0000-0000-0000-000000000001', '[{"adGroupId": 1, "campaignId": 1, "name": "AG1", "status": "ENABLED", "type": "SEARCH_STANDARD"}]'::jsonb);
SELECT is((SELECT count(*)::int FROM ads.ad_groups WHERE customer_id = 'test-cid'), 1, 'upsert_ad_groups works');

-- Test upsert_ads
SELECT ads.upsert_ads('test-cid', 'a0000000-0000-0000-0000-000000000001', '[{"adId": 1, "adGroupId": 1, "adType": "RESPONSIVE_SEARCH_AD", "status": "ENABLED", "approvalStatus": "APPROVED", "reviewStatus": "REVIEWED"}]'::jsonb);
SELECT is((SELECT count(*)::int FROM ads.ads WHERE customer_id = 'test-cid'), 1, 'upsert_ads works');

-- Test upsert_assets
SELECT ads.upsert_assets('test-cid', 'a0000000-0000-0000-0000-000000000001', '[{"assetId": 1, "assetType": "TEXT", "textContent": "Hello World", "globalApproval": "APPROVED"}]'::jsonb);
SELECT is((SELECT count(*)::int FROM ads.assets WHERE customer_id = 'test-cid'), 1, 'upsert_assets works');

-- Test upsert_asset_links
SELECT ads.upsert_asset_links('test-cid', 'a0000000-0000-0000-0000-000000000001', '[{"linkLevel": "AD", "assetId": 1, "fieldType": "HEADLINE", "campaignId": 1, "adGroupId": 1, "adId": 1, "approvalStatus": "APPROVED", "linkStatus": "ENABLED"}]'::jsonb);
SELECT is((SELECT count(*)::int FROM ads.asset_links WHERE customer_id = 'test-cid'), 1, 'upsert_asset_links works');

SELECT * FROM finish();
ROLLBACK;
