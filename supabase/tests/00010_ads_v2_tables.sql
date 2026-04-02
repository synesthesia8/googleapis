BEGIN;
SELECT plan(10);

SELECT has_schema('ads_v2', 'ads_v2 schema should exist');
SELECT has_table('ads_v2', 'accounts', 'accounts table');
SELECT has_table('ads_v2', 'campaigns', 'campaigns table');
SELECT has_table('ads_v2', 'ad_groups', 'ad_groups table');
SELECT has_table('ads_v2', 'ads', 'ads table');
SELECT has_table('ads_v2', 'assets', 'assets table');
SELECT has_table('ads_v2', 'customer_assets', 'customer_assets table');
SELECT has_table('ads_v2', 'campaign_assets', 'campaign_assets table');
SELECT has_table('ads_v2', 'ad_group_assets', 'ad_group_assets table');
SELECT has_table('ads_v2', 'ad_group_ad_asset_view', 'ad_group_ad_asset_view table');

SELECT * FROM finish();
ROLLBACK;
