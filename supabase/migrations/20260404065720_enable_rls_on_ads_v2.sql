-- Enable RLS on all ads_v2 tables
-- No policies = no access via anon/authenticated roles
-- Service role (used by Edge Function) bypasses RLS

ALTER TABLE ads_v2.accounts ENABLE ROW LEVEL SECURITY;
ALTER TABLE ads_v2.campaigns ENABLE ROW LEVEL SECURITY;
ALTER TABLE ads_v2.ad_groups ENABLE ROW LEVEL SECURITY;
ALTER TABLE ads_v2.ads ENABLE ROW LEVEL SECURITY;
ALTER TABLE ads_v2.assets ENABLE ROW LEVEL SECURITY;
ALTER TABLE ads_v2.customer_assets ENABLE ROW LEVEL SECURITY;
ALTER TABLE ads_v2.campaign_assets ENABLE ROW LEVEL SECURITY;
ALTER TABLE ads_v2.ad_group_assets ENABLE ROW LEVEL SECURITY;
ALTER TABLE ads_v2.ad_group_ad_asset_view ENABLE ROW LEVEL SECURITY;
ALTER TABLE ads_v2.entity_ledger ENABLE ROW LEVEL SECURITY;
ALTER TABLE ads_v2.sync_runs ENABLE ROW LEVEL SECURITY;
