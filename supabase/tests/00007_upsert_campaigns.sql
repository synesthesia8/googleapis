BEGIN;
SELECT plan(5);

-- Seed account
INSERT INTO ads.accounts (customer_id, descriptive_name) VALUES ('test-cid', 'Test');

-- Test 1: Insert new campaigns
SELECT ads.upsert_campaigns('test-cid', 'a0000000-0000-0000-0000-000000000001', '[
  {"campaignId": 1, "name": "Campaign A", "status": "ENABLED", "servingStatus": "SERVING", "channelType": "SEARCH"},
  {"campaignId": 2, "name": "Campaign B", "status": "PAUSED", "servingStatus": "NONE", "channelType": "SEARCH"}
]'::jsonb);

SELECT is(
  (SELECT count(*)::int FROM ads.campaigns WHERE customer_id = 'test-cid'),
  2,
  'Should insert 2 campaigns'
);

-- Test 2: Upsert updates existing
SELECT ads.upsert_campaigns('test-cid', 'a0000000-0000-0000-0000-000000000002', '[
  {"campaignId": 1, "name": "Campaign A Renamed", "status": "ENABLED", "servingStatus": "SERVING", "channelType": "SEARCH"}
]'::jsonb);

SELECT is(
  (SELECT name FROM ads.campaigns WHERE campaign_id = 1 AND customer_id = 'test-cid'),
  'Campaign A Renamed',
  'Should update campaign name on upsert'
);

-- Test 3: last_sync_id is stamped
SELECT is(
  (SELECT last_sync_id::text FROM ads.campaigns WHERE campaign_id = 1 AND customer_id = 'test-cid'),
  'a0000000-0000-0000-0000-000000000002',
  'last_sync_id should be updated on upsert'
);

-- Test 4: No status changes yet (status did not change)
SELECT is(
  (SELECT count(*)::int FROM ads.status_changes WHERE entity_type = 'CAMPAIGN'),
  0,
  'No status changes when status values unchanged'
);

-- Test 5: Trigger fires when status changes
SELECT ads.upsert_campaigns('test-cid', 'a0000000-0000-0000-0000-000000000003', '[
  {"campaignId": 1, "name": "Campaign A Renamed", "status": "PAUSED", "servingStatus": "NONE", "channelType": "SEARCH"}
]'::jsonb);

SELECT is(
  (SELECT count(*)::int FROM ads.status_changes WHERE entity_type = 'CAMPAIGN'),
  2,
  'Should log 2 status changes (status + serving_status both changed)'
);

SELECT * FROM finish();
ROLLBACK;
