BEGIN;
SELECT plan(9);

SELECT ads_v2.upsert_accounts('test-cid', 'a0000000-0000-0000-0000-000000000001',
  '[{"customer": {"id": "test-cid", "descriptiveName": "Test"}}]'::jsonb);
SELECT is((SELECT count(*)::int FROM ads_v2.accounts), 1, 'upsert_accounts');

SELECT ads_v2.upsert_campaigns('test-cid', 'a0000000-0000-0000-0000-000000000001',
  '[{"campaign": {"id": "1", "name": "C1", "status": "ENABLED"}}]'::jsonb);
SELECT is((SELECT count(*)::int FROM ads_v2.campaigns), 1, 'upsert_campaigns');

SELECT ads_v2.upsert_ad_groups('test-cid', 'a0000000-0000-0000-0000-000000000001',
  '[{"adGroup": {"id": "1", "name": "AG1"}, "campaign": {"id": "1"}}]'::jsonb);
SELECT is((SELECT count(*)::int FROM ads_v2.ad_groups), 1, 'upsert_ad_groups');

SELECT ads_v2.upsert_ads('test-cid', 'a0000000-0000-0000-0000-000000000001',
  '[{"adGroupAd": {"ad": {"id": "1", "type": "RSA"}, "status": "ENABLED"}, "adGroup": {"id": "1"}}]'::jsonb);
SELECT is((SELECT count(*)::int FROM ads_v2.ads), 1, 'upsert_ads');

SELECT ads_v2.upsert_assets('test-cid', 'a0000000-0000-0000-0000-000000000001',
  '[{"asset": {"id": "1", "type": "TEXT", "textAsset": {"text": "Hello"}}}]'::jsonb);
SELECT is((SELECT count(*)::int FROM ads_v2.assets), 1, 'upsert_assets');

SELECT ads_v2.upsert_customer_assets('test-cid', 'a0000000-0000-0000-0000-000000000001',
  '[{"asset": {"id": "1"}, "customerAsset": {"fieldType": "SITELINK"}}]'::jsonb);
SELECT is((SELECT count(*)::int FROM ads_v2.customer_assets), 1, 'upsert_customer_assets');

SELECT ads_v2.upsert_campaign_assets('test-cid', 'a0000000-0000-0000-0000-000000000001',
  '[{"asset": {"id": "1"}, "campaign": {"id": "1"}, "campaignAsset": {"fieldType": "SITELINK"}}]'::jsonb);
SELECT is((SELECT count(*)::int FROM ads_v2.campaign_assets), 1, 'upsert_campaign_assets');

SELECT ads_v2.upsert_ad_group_assets('test-cid', 'a0000000-0000-0000-0000-000000000001',
  '[{"asset": {"id": "1"}, "adGroup": {"id": "1"}, "adGroupAsset": {"fieldType": "SITELINK"}}]'::jsonb);
SELECT is((SELECT count(*)::int FROM ads_v2.ad_group_assets), 1, 'upsert_ad_group_assets');

SELECT ads_v2.upsert_ad_group_ad_asset_view('test-cid', 'a0000000-0000-0000-0000-000000000001',
  '[{"asset": {"id": "1"}, "adGroup": {"id": "1"}, "adGroupAd": {"ad": {"id": "1"}}, "adGroupAdAssetView": {"fieldType": "HEADLINE"}}]'::jsonb);
SELECT is((SELECT count(*)::int FROM ads_v2.ad_group_ad_asset_view), 1, 'upsert_ad_group_ad_asset_view');

SELECT * FROM finish();
ROLLBACK;
