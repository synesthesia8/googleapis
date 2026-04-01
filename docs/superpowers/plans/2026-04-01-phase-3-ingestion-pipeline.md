# Phase 3: Ingestion Pipeline (Edge Function + RPC Functions)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the Supabase Edge Function gateway and Postgres RPC upsert functions so that data can be pushed into the database via HTTP. Prove it works with manual curl requests before connecting a Google Ads Script.

**Architecture:** One Edge Function receives all POST requests, verifies Google OAuth, routes to the correct `ads.upsert_{resource_type}()` RPC function. Each RPC function parses JSONB, upserts into the correct table, and stamps `last_sync_id`. A `finalize_sync` RPC handles deletion detection, bootstrap, and cascade view refresh.

**Tech Stack:** Supabase Edge Functions (Deno/TypeScript), PL/pgSQL, curl for testing

**Depends on:** Phase 2 (all tables, triggers, cascade view exist)

**Spec reference:** `docs/superpowers/specs/2026-04-01-google-ads-asset-policy-monitor-design.md` — Upsert RPC Functions, Supabase Edge Function, Concurrency Control, Handling Deletions, First Sync Bootstrap sections

---

### Task 1: Create the `ads.upsert_campaigns` RPC function

**Files:**
- Create: `supabase/migrations/00008_create_upsert_campaigns.sql`
- Create: `supabase/tests/00007_upsert_campaigns.sql`

- [ ] **Step 1: Write the test**

```sql
-- supabase/tests/00007_upsert_campaigns.sql
BEGIN;
SELECT plan(5);

-- Seed account
INSERT INTO ads.accounts (customer_id, descriptive_name) VALUES ('test-cid', 'Test');

-- Test 1: Insert new campaigns
SELECT ads.upsert_campaigns('test-cid', 'sync-001', '[
  {"campaignId": 1, "name": "Campaign A", "status": "ENABLED", "servingStatus": "SERVING", "channelType": "SEARCH"},
  {"campaignId": 2, "name": "Campaign B", "status": "PAUSED", "servingStatus": "NONE", "channelType": "SEARCH"}
]'::jsonb);

SELECT is(
  (SELECT count(*)::int FROM ads.campaigns WHERE customer_id = 'test-cid'),
  2,
  'Should insert 2 campaigns'
);

-- Test 2: Upsert updates existing
SELECT ads.upsert_campaigns('test-cid', 'sync-002', '[
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
  'sync-002',
  'last_sync_id should be updated on upsert'
);

-- Test 4: Status change triggers fire
SELECT is(
  (SELECT count(*)::int FROM ads.status_changes WHERE entity_type = 'CAMPAIGN'),
  0,
  'No status changes yet (status did not change)'
);

-- Test 5: Trigger fires when status changes
SELECT ads.upsert_campaigns('test-cid', 'sync-003', '[
  {"campaignId": 1, "name": "Campaign A Renamed", "status": "PAUSED", "servingStatus": "NONE", "channelType": "SEARCH"}
]'::jsonb);

SELECT is(
  (SELECT count(*)::int FROM ads.status_changes WHERE entity_type = 'CAMPAIGN'),
  2,
  'Should log 2 status changes (status + serving_status both changed)'
);

SELECT * FROM finish();
ROLLBACK;
```

- [ ] **Step 2: Run test to verify it fails**

```bash
supabase test db
```

- [ ] **Step 3: Write the RPC function**

```sql
-- supabase/migrations/00008_create_upsert_campaigns.sql

CREATE OR REPLACE FUNCTION ads.upsert_campaigns(
  p_customer_id text,
  p_sync_id text,
  p_rows jsonb
) RETURNS void AS $$
BEGIN
  INSERT INTO ads.campaigns (
    campaign_id, customer_id, name, status, serving_status,
    channel_type, channel_sub_type, bidding_strategy,
    start_date, end_date, budget_amount_micros,
    last_checked_at, last_sync_id
  )
  SELECT
    (r->>'campaignId')::bigint,
    p_customer_id,
    r->>'name',
    r->>'status',
    r->>'servingStatus',
    r->>'channelType',
    r->>'channelSubType',
    r->>'biddingStrategy',
    (r->>'startDate')::date,
    (r->>'endDate')::date,
    (r->>'budgetAmountMicros')::bigint,
    now(),
    p_sync_id::uuid
  FROM jsonb_array_elements(p_rows) AS r
  ON CONFLICT (campaign_id, customer_id)
  DO UPDATE SET
    name = EXCLUDED.name,
    status = EXCLUDED.status,
    serving_status = EXCLUDED.serving_status,
    channel_type = EXCLUDED.channel_type,
    channel_sub_type = EXCLUDED.channel_sub_type,
    bidding_strategy = EXCLUDED.bidding_strategy,
    start_date = EXCLUDED.start_date,
    end_date = EXCLUDED.end_date,
    budget_amount_micros = EXCLUDED.budget_amount_micros,
    last_checked_at = now(),
    last_sync_id = EXCLUDED.last_sync_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
```

- [ ] **Step 4: Apply and run tests**

```bash
supabase db reset && supabase test db
```

Expected: All tests pass.

- [ ] **Step 5: Commit**

```bash
git add supabase/migrations/ supabase/tests/
git commit -m "feat: create upsert_campaigns RPC function"
```

---

### Task 2: Create remaining upsert RPC functions

**Files:**
- Create: `supabase/migrations/00009_create_upsert_ad_groups.sql`
- Create: `supabase/migrations/00010_create_upsert_ads.sql`
- Create: `supabase/migrations/00011_create_upsert_assets.sql`
- Create: `supabase/migrations/00012_create_upsert_asset_links.sql`
- Create: `supabase/migrations/00013_create_upsert_accounts.sql`
- Create: `supabase/tests/00008_upsert_functions.sql`

Each function follows the exact same pattern as `upsert_campaigns` — accept `(p_customer_id, p_sync_id, p_rows jsonb)`, parse JSONB, INSERT ON CONFLICT DO UPDATE, stamp `last_sync_id` and `last_checked_at`.

- [ ] **Step 1: Write test covering all upsert functions**

```sql
-- supabase/tests/00008_upsert_functions.sql
BEGIN;
SELECT plan(5);

-- Seed
INSERT INTO ads.accounts (customer_id, descriptive_name) VALUES ('test-cid', 'Test');

-- Test upsert_campaigns (already tested in 00007, quick sanity check)
SELECT ads.upsert_campaigns('test-cid', 'sync-1', '[{"campaignId": 1, "name": "C1", "status": "ENABLED", "servingStatus": "SERVING", "channelType": "SEARCH"}]'::jsonb);
SELECT is((SELECT count(*)::int FROM ads.campaigns), 1, 'upsert_campaigns works');

-- Test upsert_ad_groups
SELECT ads.upsert_ad_groups('test-cid', 'sync-1', '[{"adGroupId": 1, "campaignId": 1, "name": "AG1", "status": "ENABLED", "type": "SEARCH_STANDARD"}]'::jsonb);
SELECT is((SELECT count(*)::int FROM ads.ad_groups), 1, 'upsert_ad_groups works');

-- Test upsert_ads
SELECT ads.upsert_ads('test-cid', 'sync-1', '[{"adId": 1, "adGroupId": 1, "adType": "RESPONSIVE_SEARCH_AD", "status": "ENABLED", "approvalStatus": "APPROVED", "reviewStatus": "REVIEWED"}]'::jsonb);
SELECT is((SELECT count(*)::int FROM ads.ads), 1, 'upsert_ads works');

-- Test upsert_assets
SELECT ads.upsert_assets('test-cid', 'sync-1', '[{"assetId": 1, "assetType": "TEXT", "textContent": "Hello World", "globalApproval": "APPROVED"}]'::jsonb);
SELECT is((SELECT count(*)::int FROM ads.assets), 1, 'upsert_assets works');

-- Test upsert_asset_links
SELECT ads.upsert_asset_links('test-cid', 'sync-1', '[{"linkLevel": "AD", "assetId": 1, "fieldType": "HEADLINE", "campaignId": 1, "adGroupId": 1, "adId": 1, "approvalStatus": "APPROVED", "linkStatus": "ENABLED"}]'::jsonb);
SELECT is((SELECT count(*)::int FROM ads.asset_links), 1, 'upsert_asset_links works');

SELECT * FROM finish();
ROLLBACK;
```

- [ ] **Step 2: Write `upsert_ad_groups`**

```sql
-- supabase/migrations/00009_create_upsert_ad_groups.sql

CREATE OR REPLACE FUNCTION ads.upsert_ad_groups(
  p_customer_id text,
  p_sync_id text,
  p_rows jsonb
) RETURNS void AS $$
BEGIN
  INSERT INTO ads.ad_groups (
    ad_group_id, customer_id, campaign_id, name, status, type, cpc_bid_micros,
    last_checked_at, last_sync_id
  )
  SELECT
    (r->>'adGroupId')::bigint,
    p_customer_id,
    (r->>'campaignId')::bigint,
    r->>'name',
    r->>'status',
    r->>'type',
    (r->>'cpcBidMicros')::bigint,
    now(),
    p_sync_id::uuid
  FROM jsonb_array_elements(p_rows) AS r
  ON CONFLICT (ad_group_id, customer_id)
  DO UPDATE SET
    campaign_id = EXCLUDED.campaign_id,
    name = EXCLUDED.name,
    status = EXCLUDED.status,
    type = EXCLUDED.type,
    cpc_bid_micros = EXCLUDED.cpc_bid_micros,
    last_checked_at = now(),
    last_sync_id = EXCLUDED.last_sync_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
```

- [ ] **Step 3: Write `upsert_ads`**

```sql
-- supabase/migrations/00010_create_upsert_ads.sql

CREATE OR REPLACE FUNCTION ads.upsert_ads(
  p_customer_id text,
  p_sync_id text,
  p_rows jsonb
) RETURNS void AS $$
BEGIN
  INSERT INTO ads.ads (
    ad_id, customer_id, ad_group_id, ad_type, status,
    approval_status, review_status, ad_strength, policy_topics, final_urls,
    last_checked_at, last_sync_id
  )
  SELECT
    (r->>'adId')::bigint,
    p_customer_id,
    (r->>'adGroupId')::bigint,
    r->>'adType',
    r->>'status',
    r->>'approvalStatus',
    r->>'reviewStatus',
    r->>'adStrength',
    (r->'policyTopics')::jsonb,
    CASE WHEN r->'finalUrls' IS NOT NULL
      THEN ARRAY(SELECT jsonb_array_elements_text(r->'finalUrls'))
      ELSE NULL
    END,
    now(),
    p_sync_id::uuid
  FROM jsonb_array_elements(p_rows) AS r
  ON CONFLICT (ad_id, customer_id)
  DO UPDATE SET
    ad_group_id = EXCLUDED.ad_group_id,
    ad_type = EXCLUDED.ad_type,
    status = EXCLUDED.status,
    approval_status = EXCLUDED.approval_status,
    review_status = EXCLUDED.review_status,
    ad_strength = EXCLUDED.ad_strength,
    policy_topics = EXCLUDED.policy_topics,
    final_urls = EXCLUDED.final_urls,
    last_checked_at = now(),
    last_sync_id = EXCLUDED.last_sync_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
```

- [ ] **Step 4: Write `upsert_assets`**

```sql
-- supabase/migrations/00011_create_upsert_assets.sql

CREATE OR REPLACE FUNCTION ads.upsert_assets(
  p_customer_id text,
  p_sync_id text,
  p_rows jsonb
) RETURNS void AS $$
BEGIN
  INSERT INTO ads.assets (
    asset_id, customer_id, name, asset_type,
    text_content, image_url, image_width, image_height,
    youtube_video_id, sitelink_text, sitelink_desc1, sitelink_desc2,
    callout_text, snippet_header, snippet_values, phone_number,
    global_approval, global_review, global_policy_topics,
    last_checked_at, last_sync_id
  )
  SELECT
    (r->>'assetId')::bigint,
    p_customer_id,
    r->>'name',
    r->>'assetType',
    r->>'textContent',
    r->>'imageUrl',
    (r->>'imageWidth')::int,
    (r->>'imageHeight')::int,
    r->>'youtubeVideoId',
    r->>'sitelinkText',
    r->>'sitelinkDesc1',
    r->>'sitelinkDesc2',
    r->>'calloutText',
    r->>'snippetHeader',
    CASE WHEN r->'snippetValues' IS NOT NULL
      THEN ARRAY(SELECT jsonb_array_elements_text(r->'snippetValues'))
      ELSE NULL
    END,
    r->>'phoneNumber',
    r->>'globalApproval',
    r->>'globalReview',
    (r->'globalPolicyTopics')::jsonb,
    now(),
    p_sync_id::uuid
  FROM jsonb_array_elements(p_rows) AS r
  ON CONFLICT (asset_id, customer_id)
  DO UPDATE SET
    name = EXCLUDED.name,
    asset_type = EXCLUDED.asset_type,
    text_content = EXCLUDED.text_content,
    image_url = EXCLUDED.image_url,
    image_width = EXCLUDED.image_width,
    image_height = EXCLUDED.image_height,
    youtube_video_id = EXCLUDED.youtube_video_id,
    sitelink_text = EXCLUDED.sitelink_text,
    sitelink_desc1 = EXCLUDED.sitelink_desc1,
    sitelink_desc2 = EXCLUDED.sitelink_desc2,
    callout_text = EXCLUDED.callout_text,
    snippet_header = EXCLUDED.snippet_header,
    snippet_values = EXCLUDED.snippet_values,
    phone_number = EXCLUDED.phone_number,
    global_approval = EXCLUDED.global_approval,
    global_review = EXCLUDED.global_review,
    global_policy_topics = EXCLUDED.global_policy_topics,
    last_checked_at = now(),
    last_sync_id = EXCLUDED.last_sync_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
```

- [ ] **Step 5: Write `upsert_asset_links`**

```sql
-- supabase/migrations/00012_create_upsert_asset_links.sql

CREATE OR REPLACE FUNCTION ads.upsert_asset_links(
  p_customer_id text,
  p_sync_id text,
  p_rows jsonb
) RETURNS void AS $$
BEGIN
  INSERT INTO ads.asset_links (
    customer_id, link_level, asset_id, field_type,
    campaign_id, ad_group_id, ad_id,
    link_status, approval_status, review_status,
    primary_status, primary_status_reasons, policy_topics,
    is_enabled, performance_label, pinned_field, asset_source,
    last_sync_id, last_checked_at
  )
  SELECT
    p_customer_id,
    r->>'linkLevel',
    (r->>'assetId')::bigint,
    r->>'fieldType',
    (r->>'campaignId')::bigint,
    (r->>'adGroupId')::bigint,
    (r->>'adId')::bigint,
    r->>'linkStatus',
    r->>'approvalStatus',
    r->>'reviewStatus',
    r->>'primaryStatus',
    CASE WHEN r->'primaryStatusReasons' IS NOT NULL
      THEN ARRAY(SELECT jsonb_array_elements_text(r->'primaryStatusReasons'))
      ELSE NULL
    END,
    (r->'policyTopics')::jsonb,
    (r->>'isEnabled')::boolean,
    r->>'performanceLabel',
    r->>'pinnedField',
    r->>'assetSource',
    p_sync_id::uuid,
    now()
  FROM jsonb_array_elements(p_rows) AS r
  ON CONFLICT (customer_id, link_level, asset_id, field_type,
               COALESCE(campaign_id, 0), COALESCE(ad_group_id, 0), COALESCE(ad_id, 0))
  DO UPDATE SET
    link_status = EXCLUDED.link_status,
    approval_status = EXCLUDED.approval_status,
    review_status = EXCLUDED.review_status,
    primary_status = EXCLUDED.primary_status,
    primary_status_reasons = EXCLUDED.primary_status_reasons,
    policy_topics = EXCLUDED.policy_topics,
    is_enabled = EXCLUDED.is_enabled,
    performance_label = EXCLUDED.performance_label,
    pinned_field = EXCLUDED.pinned_field,
    asset_source = EXCLUDED.asset_source,
    last_sync_id = EXCLUDED.last_sync_id,
    last_checked_at = now();
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
```

- [ ] **Step 6: Write `upsert_accounts`**

```sql
-- supabase/migrations/00013_create_upsert_accounts.sql

CREATE OR REPLACE FUNCTION ads.upsert_accounts(
  p_customer_id text,
  p_sync_id text,
  p_rows jsonb
) RETURNS void AS $$
BEGIN
  INSERT INTO ads.accounts (
    customer_id, descriptive_name, currency_code, time_zone,
    is_mcc, mcc_customer_id, status
  )
  SELECT
    p_customer_id,
    r->>'descriptiveName',
    r->>'currencyCode',
    r->>'timeZone',
    (r->>'isMcc')::boolean,
    r->>'mccCustomerId',
    r->>'status'
  FROM jsonb_array_elements(p_rows) AS r
  ON CONFLICT (customer_id)
  DO UPDATE SET
    descriptive_name = EXCLUDED.descriptive_name,
    currency_code = EXCLUDED.currency_code,
    time_zone = EXCLUDED.time_zone,
    is_mcc = EXCLUDED.is_mcc,
    mcc_customer_id = EXCLUDED.mcc_customer_id,
    status = EXCLUDED.status,
    updated_at = now();
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
```

- [ ] **Step 7: Apply and run tests**

```bash
supabase db reset && supabase test db
```

Expected: All tests pass.

- [ ] **Step 8: Commit**

```bash
git add supabase/migrations/ supabase/tests/
git commit -m "feat: create all upsert RPC functions (accounts, ad_groups, ads, assets, asset_links)"
```

---

### Task 3: Create `finalize_sync` RPC function

**Files:**
- Create: `supabase/migrations/00014_create_finalize_sync.sql`
- Create: `supabase/tests/00009_finalize_sync.sql`

- [ ] **Step 1: Write the test**

```sql
-- supabase/tests/00009_finalize_sync.sql
BEGIN;
SELECT plan(3);

-- Seed: full hierarchy
INSERT INTO ads.accounts (customer_id) VALUES ('test-cid');
SELECT ads.upsert_campaigns('test-cid', 'sync-1', '[{"campaignId": 1, "name": "C1", "status": "ENABLED", "servingStatus": "SERVING", "channelType": "SEARCH"}]'::jsonb);
SELECT ads.upsert_ad_groups('test-cid', 'sync-1', '[{"adGroupId": 1, "campaignId": 1, "name": "AG1", "status": "ENABLED"}]'::jsonb);
SELECT ads.upsert_ads('test-cid', 'sync-1', '[{"adId": 1, "adGroupId": 1, "adType": "RESPONSIVE_SEARCH_AD", "status": "ENABLED", "approvalStatus": "APPROVED"}]'::jsonb);
SELECT ads.upsert_assets('test-cid', 'sync-1', '[{"assetId": 1, "assetType": "TEXT", "textContent": "Hello", "globalApproval": "APPROVED"}]'::jsonb);
SELECT ads.upsert_asset_links('test-cid', 'sync-1', '[{"linkLevel": "AD", "assetId": 1, "fieldType": "HEADLINE", "campaignId": 1, "adGroupId": 1, "adId": 1, "approvalStatus": "APPROVED", "linkStatus": "ENABLED"}]'::jsonb);

-- Create sync run
INSERT INTO ads.sync_runs (id, customer_id, is_first_sync) VALUES ('sync-1', 'test-cid', true);

-- Sync 2: asset_link disappears (not in this sync)
SELECT ads.upsert_asset_links('test-cid', 'sync-2', '[]'::jsonb);
INSERT INTO ads.sync_runs (id, customer_id) VALUES ('sync-2', 'test-cid');

-- Finalize
SELECT ads.finalize_sync('test-cid', 'sync-2');

-- Test 1: Missing asset_link should be marked REMOVED
SELECT is(
  (SELECT link_status FROM ads.asset_links WHERE id = 1),
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
  (SELECT status FROM ads.sync_runs WHERE id = 'sync-2'),
  'completed',
  'Sync run should be marked completed'
);

SELECT * FROM finish();
ROLLBACK;
```

- [ ] **Step 2: Write the function**

```sql
-- supabase/migrations/00014_create_finalize_sync.sql

CREATE OR REPLACE FUNCTION ads.finalize_sync(
  p_customer_id text,
  p_sync_id text
) RETURNS void AS $$
BEGIN
  -- Acquire advisory lock for this customer (transaction-scoped)
  PERFORM pg_advisory_xact_lock(hashtext(p_customer_id));

  -- Mark unseen asset_links as REMOVED
  UPDATE ads.asset_links
  SET link_status = 'REMOVED', updated_at = now()
  WHERE customer_id = p_customer_id
    AND last_sync_id IS DISTINCT FROM p_sync_id::uuid
    AND link_status != 'REMOVED';

  -- Refresh cascade view
  REFRESH MATERIALIZED VIEW CONCURRENTLY ads.cascade_status;

  -- Mark sync as completed
  UPDATE ads.sync_runs
  SET status = 'completed', completed_at = now()
  WHERE id = p_sync_id::uuid;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
```

- [ ] **Step 3: Apply and run tests**

```bash
supabase db reset && supabase test db
```

Expected: All tests pass.

- [ ] **Step 4: Commit**

```bash
git add supabase/migrations/ supabase/tests/
git commit -m "feat: create finalize_sync RPC (deletion detection, cascade refresh)"
```

---

### Task 4: Create the Edge Function

**Files:**
- Create: `supabase/functions/ingest-gads/index.ts`

- [ ] **Step 1: Generate the Edge Function**

```bash
supabase functions new ingest-gads
```

- [ ] **Step 2: Write the Edge Function**

```typescript
// supabase/functions/ingest-gads/index.ts
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const ALLOWED_EMAILS = (Deno.env.get('ALLOWED_EMAILS') || '').split(',').map(e => e.trim())
const tokenCache = new Map<string, { email: string; expiresAt: number }>()

Deno.serve(async (req) => {
  if (req.method !== 'POST') {
    return new Response('Method not allowed', { status: 405 })
  }

  // ── Auth ────────────────────────────────────────────────────
  const token = req.headers.get('Authorization')?.replace('Bearer ', '')
  if (!token) return new Response('No token', { status: 401 })

  let payload: any
  try {
    payload = await req.json()
  } catch {
    return new Response('Invalid JSON', { status: 400 })
  }

  const syncId = payload.sync_id
  if (!syncId) return new Response('Missing sync_id', { status: 400 })

  // Check cache first
  const cached = tokenCache.get(syncId)
  if (!cached || cached.expiresAt < Date.now()) {
    // Verify with Google
    const googleRes = await fetch(
      `https://oauth2.googleapis.com/tokeninfo?access_token=${token}`
    )
    if (!googleRes.ok) return new Response('Invalid token', { status: 401 })

    const info = await googleRes.json()
    if (!ALLOWED_EMAILS.includes(info.email)) {
      return new Response('Forbidden', { status: 403 })
    }

    // Cache for 60 minutes
    tokenCache.set(syncId, { email: info.email, expiresAt: Date.now() + 3600000 })
  }

  // ── Validate payload ────────────────────────────────────────
  const { customer_id, resource_type, rows } = payload
  if (!customer_id || !resource_type || !Array.isArray(rows)) {
    return new Response('Invalid payload: need customer_id, resource_type, rows[]', { status: 400 })
  }

  // ── Route to correct RPC ────────────────────────────────────
  const supabase = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
  )

  const rpcName = `upsert_${resource_type}`
  const validRpcNames = [
    'upsert_accounts', 'upsert_campaigns', 'upsert_ad_groups',
    'upsert_ads', 'upsert_assets', 'upsert_asset_links',
    'finalize_sync'
  ]

  if (resource_type === 'finalize') {
    const { error } = await supabase.schema('ads').rpc('finalize_sync', {
      p_customer_id: customer_id,
      p_sync_id: syncId,
    })
    if (error) return new Response(JSON.stringify({ error: error.message }), { status: 500 })
    return new Response(JSON.stringify({ finalized: true }), { status: 200 })
  }

  if (!validRpcNames.includes(rpcName)) {
    return new Response(`Unknown resource_type: ${resource_type}`, { status: 400 })
  }

  const { error } = await supabase.schema('ads').rpc(rpcName, {
    p_customer_id: customer_id,
    p_sync_id: syncId,
    p_rows: rows,
  })

  if (error) {
    console.error(`RPC ${rpcName} failed:`, error)
    return new Response(JSON.stringify({ error: error.message }), { status: 500 })
  }

  return new Response(JSON.stringify({ inserted: rows.length }), { status: 200 })
})
```

- [ ] **Step 3: Test locally with curl (no auth for local dev)**

Start the Edge Function locally:

```bash
supabase functions serve ingest-gads --no-verify-jwt
```

In another terminal, send test data:

```bash
curl -X POST http://localhost:54321/functions/v1/ingest-gads \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer test-token" \
  -d '{
    "sync_id": "00000000-0000-0000-0000-000000000001",
    "customer_id": "123-456-7890",
    "resource_type": "accounts",
    "rows": [{"descriptiveName": "Curl Test Account", "currencyCode": "AUD", "timeZone": "Australia/Sydney"}]
  }'
```

Expected: `{"inserted": 1}`.

Verify it landed:

```bash
supabase db execute --sql "SELECT * FROM ads.accounts WHERE customer_id = '123-456-7890';"
```

Expected: One row with `descriptive_name = 'Curl Test Account'`.

- [ ] **Step 4: Commit**

```bash
git add supabase/functions/
git commit -m "feat: create ingest-gads Edge Function with Google OAuth verification"
```

---

### Task 5: End-to-end test with curl (full sync simulation)

**Files:** None (manual testing)

- [ ] **Step 1: Reset database and run a simulated full sync via curl**

```bash
supabase db reset
supabase functions serve ingest-gads --no-verify-jwt &
```

```bash
SYNC_ID="00000000-0000-0000-0000-000000000099"
CID="123-456-7890"
URL="http://localhost:54321/functions/v1/ingest-gads"
AUTH="Authorization: Bearer test"

# 1. Account
curl -s -X POST $URL -H "Content-Type: application/json" -H "$AUTH" -d "{
  \"sync_id\": \"$SYNC_ID\", \"customer_id\": \"$CID\", \"resource_type\": \"accounts\",
  \"rows\": [{\"descriptiveName\": \"E2E Test\", \"currencyCode\": \"AUD\", \"timeZone\": \"Australia/Sydney\"}]
}"

# 2. Campaign
curl -s -X POST $URL -H "Content-Type: application/json" -H "$AUTH" -d "{
  \"sync_id\": \"$SYNC_ID\", \"customer_id\": \"$CID\", \"resource_type\": \"campaigns\",
  \"rows\": [{\"campaignId\": 1, \"name\": \"Brand\", \"status\": \"ENABLED\", \"servingStatus\": \"SERVING\", \"channelType\": \"SEARCH\"}]
}"

# 3. Ad Group
curl -s -X POST $URL -H "Content-Type: application/json" -H "$AUTH" -d "{
  \"sync_id\": \"$SYNC_ID\", \"customer_id\": \"$CID\", \"resource_type\": \"ad_groups\",
  \"rows\": [{\"adGroupId\": 1, \"campaignId\": 1, \"name\": \"Brand Exact\", \"status\": \"ENABLED\"}]
}"

# 4. Ad
curl -s -X POST $URL -H "Content-Type: application/json" -H "$AUTH" -d "{
  \"sync_id\": \"$SYNC_ID\", \"customer_id\": \"$CID\", \"resource_type\": \"ads\",
  \"rows\": [{\"adId\": 1, \"adGroupId\": 1, \"adType\": \"RESPONSIVE_SEARCH_AD\", \"status\": \"ENABLED\", \"approvalStatus\": \"DISAPPROVED\"}]
}"

# 5. Assets
curl -s -X POST $URL -H "Content-Type: application/json" -H "$AUTH" -d "{
  \"sync_id\": \"$SYNC_ID\", \"customer_id\": \"$CID\", \"resource_type\": \"assets\",
  \"rows\": [{\"assetId\": 1, \"assetType\": \"TEXT\", \"textContent\": \"Buy cheap meds\", \"globalApproval\": \"DISAPPROVED\"}]
}"

# 6. Asset Links
curl -s -X POST $URL -H "Content-Type: application/json" -H "$AUTH" -d "{
  \"sync_id\": \"$SYNC_ID\", \"customer_id\": \"$CID\", \"resource_type\": \"asset_links\",
  \"rows\": [{\"linkLevel\": \"AD\", \"assetId\": 1, \"fieldType\": \"HEADLINE\", \"campaignId\": 1, \"adGroupId\": 1, \"adId\": 1, \"approvalStatus\": \"DISAPPROVED\", \"linkStatus\": \"ENABLED\"}]
}"

# 7. Create sync run and finalize
supabase db execute --sql "INSERT INTO ads.sync_runs (id, customer_id, is_first_sync) VALUES ('$SYNC_ID', '$CID', true);"

curl -s -X POST $URL -H "Content-Type: application/json" -H "$AUTH" -d "{
  \"sync_id\": \"$SYNC_ID\", \"customer_id\": \"$CID\", \"resource_type\": \"finalize\",
  \"rows\": []
}"
```

- [ ] **Step 2: Query the cascade view**

```bash
supabase db execute --sql "
SELECT text_content, asset_link_approval, ad_approval, campaign_name, campaign_serving, impact_level
FROM ads.cascade_status;
"
```

Expected: One row — `Buy cheap meds | DISAPPROVED | DISAPPROVED | Brand | SERVING | AD_KILLED`.

- [ ] **Step 3: Verify no errors in Edge Function logs**

```bash
# Check the terminal running supabase functions serve
# Should show 200 responses for all requests
```

---

## Phase 3 Definition of Done

- [ ] All 6 upsert RPC functions exist and work (accounts, campaigns, ad_groups, ads, assets, asset_links)
- [ ] `finalize_sync` RPC handles deletion detection and cascade view refresh
- [ ] Edge Function receives POST, validates payload, routes to correct RPC
- [ ] Google OAuth verification with caching works (tested locally with bypass)
- [ ] Full sync simulation via curl produces correct cascade view output
- [ ] All pgTAP tests pass
- [ ] All changes committed
