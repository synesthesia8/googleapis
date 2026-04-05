# v2 Data Ingestion — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Pull everything from Google Ads into JSONB tables. No data loss. No transformation. Raw storage with typed PKs.

**Architecture:** 9 JSONB tables in `ads_v2` schema, one per GAQL resource type. Edge Function + RPC upsert functions. Google Ads Script with no transformers.

**Tech Stack:** Supabase (Postgres, Edge Functions), Google Ads Scripts, pgTAP

**Spec reference:** `docs/superpowers/specs/v2/2026-04-02-data-ingestion-v2-design.md`

---

### Task 1: Create `ads_v2` schema and all 9 tables

**Files:**
- Create: `supabase/migrations/{timestamp}_create_ads_v2.sql`
- Create: `supabase/tests/00010_ads_v2_tables.sql`

- [ ] **Step 1: Write the test**

```sql
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
```

- [ ] **Step 2: Write the migration**

```sql
CREATE SCHEMA IF NOT EXISTS ads_v2;

GRANT USAGE ON SCHEMA ads_v2 TO postgres, anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA ads_v2 GRANT ALL ON TABLES TO postgres, service_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA ads_v2 GRANT SELECT ON TABLES TO anon, authenticated;
ALTER DEFAULT PRIVILEGES IN SCHEMA ads_v2 GRANT EXECUTE ON FUNCTIONS TO postgres, service_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA ads_v2 GRANT EXECUTE ON FUNCTIONS TO anon, authenticated;

-- Accounts
CREATE TABLE ads_v2.accounts (
  customer_id     text PRIMARY KEY,
  data            jsonb NOT NULL,
  last_sync_id    uuid,
  last_checked_at timestamptz,
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now()
);

-- Campaigns
CREATE TABLE ads_v2.campaigns (
  campaign_id     bigint NOT NULL,
  customer_id     text NOT NULL,
  data            jsonb NOT NULL,
  last_sync_id    uuid,
  last_checked_at timestamptz,
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (campaign_id, customer_id)
);

-- Ad Groups
CREATE TABLE ads_v2.ad_groups (
  ad_group_id     bigint NOT NULL,
  customer_id     text NOT NULL,
  data            jsonb NOT NULL,
  last_sync_id    uuid,
  last_checked_at timestamptz,
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (ad_group_id, customer_id)
);

-- Ads
CREATE TABLE ads_v2.ads (
  ad_id           bigint NOT NULL,
  customer_id     text NOT NULL,
  data            jsonb NOT NULL,
  last_sync_id    uuid,
  last_checked_at timestamptz,
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (ad_id, customer_id)
);

-- Assets
CREATE TABLE ads_v2.assets (
  asset_id        bigint NOT NULL,
  customer_id     text NOT NULL,
  data            jsonb NOT NULL,
  last_sync_id    uuid,
  last_checked_at timestamptz,
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (asset_id, customer_id)
);

-- Customer Assets
CREATE TABLE ads_v2.customer_assets (
  customer_id     text NOT NULL,
  asset_id        bigint NOT NULL,
  field_type      text NOT NULL,
  data            jsonb NOT NULL,
  last_sync_id    uuid,
  last_checked_at timestamptz,
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (customer_id, asset_id, field_type)
);

-- Campaign Assets
CREATE TABLE ads_v2.campaign_assets (
  customer_id     text NOT NULL,
  campaign_id     bigint NOT NULL,
  asset_id        bigint NOT NULL,
  field_type      text NOT NULL,
  data            jsonb NOT NULL,
  last_sync_id    uuid,
  last_checked_at timestamptz,
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (customer_id, campaign_id, asset_id, field_type)
);

-- Ad Group Assets
CREATE TABLE ads_v2.ad_group_assets (
  customer_id     text NOT NULL,
  ad_group_id     bigint NOT NULL,
  asset_id        bigint NOT NULL,
  field_type      text NOT NULL,
  data            jsonb NOT NULL,
  last_sync_id    uuid,
  last_checked_at timestamptz,
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (customer_id, ad_group_id, asset_id, field_type)
);

-- Ad Group Ad Asset View
CREATE TABLE ads_v2.ad_group_ad_asset_view (
  customer_id     text NOT NULL,
  ad_group_id     bigint NOT NULL,
  ad_id           bigint NOT NULL,
  asset_id        bigint NOT NULL,
  field_type      text NOT NULL,
  data            jsonb NOT NULL,
  last_sync_id    uuid,
  last_checked_at timestamptz,
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (customer_id, ad_group_id, ad_id, asset_id, field_type)
);

-- Sync Runs
CREATE TABLE ads_v2.sync_runs (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  customer_id     text NOT NULL,
  started_at      timestamptz NOT NULL DEFAULT now(),
  completed_at    timestamptz,
  status          text NOT NULL DEFAULT 'running',
  rows_by_type    jsonb,
  truncation_warnings text[],
  error           text,
  CONSTRAINT valid_sync_status CHECK (status IN ('running', 'completed', 'failed'))
);
```

- [ ] **Step 3: Apply and test locally**

```bash
supabase db reset && supabase test db
```

- [ ] **Step 4: Commit and push**

---

### Task 2: Create all RPC upsert functions

**Files:**
- Create: `supabase/migrations/{timestamp}_create_ads_v2_upsert_fns.sql`
- Create: `supabase/tests/00011_ads_v2_upserts.sql`

- [ ] **Step 1: Write the test**

```sql
BEGIN;
SELECT plan(9);

-- Seed account
SELECT ads_v2.upsert_accounts('test-cid', 'a0000000-0000-0000-0000-000000000001',
  '[{"customer": {"id": "test-cid", "descriptiveName": "Test"}}]'::jsonb);
SELECT is((SELECT count(*)::int FROM ads_v2.accounts), 1, 'upsert_accounts works');

SELECT ads_v2.upsert_campaigns('test-cid', 'a0000000-0000-0000-0000-000000000001',
  '[{"campaign": {"id": "1", "name": "C1", "status": "ENABLED"}}]'::jsonb);
SELECT is((SELECT count(*)::int FROM ads_v2.campaigns), 1, 'upsert_campaigns works');

SELECT ads_v2.upsert_ad_groups('test-cid', 'a0000000-0000-0000-0000-000000000001',
  '[{"adGroup": {"id": "1", "name": "AG1"}, "campaign": {"id": "1"}}]'::jsonb);
SELECT is((SELECT count(*)::int FROM ads_v2.ad_groups), 1, 'upsert_ad_groups works');

SELECT ads_v2.upsert_ads('test-cid', 'a0000000-0000-0000-0000-000000000001',
  '[{"adGroupAd": {"ad": {"id": "1", "type": "RSA"}, "status": "ENABLED"}, "adGroup": {"id": "1"}, "campaign": {"id": "1"}}]'::jsonb);
SELECT is((SELECT count(*)::int FROM ads_v2.ads), 1, 'upsert_ads works');

SELECT ads_v2.upsert_assets('test-cid', 'a0000000-0000-0000-0000-000000000001',
  '[{"asset": {"id": "1", "type": "TEXT", "textAsset": {"text": "Hello"}}}]'::jsonb);
SELECT is((SELECT count(*)::int FROM ads_v2.assets), 1, 'upsert_assets works');

SELECT ads_v2.upsert_customer_assets('test-cid', 'a0000000-0000-0000-0000-000000000001',
  '[{"asset": {"id": "1"}, "customerAsset": {"fieldType": "SITELINK"}}]'::jsonb);
SELECT is((SELECT count(*)::int FROM ads_v2.customer_assets), 1, 'upsert_customer_assets works');

SELECT ads_v2.upsert_campaign_assets('test-cid', 'a0000000-0000-0000-0000-000000000001',
  '[{"asset": {"id": "1"}, "campaign": {"id": "1"}, "campaignAsset": {"fieldType": "SITELINK"}}]'::jsonb);
SELECT is((SELECT count(*)::int FROM ads_v2.campaign_assets), 1, 'upsert_campaign_assets works');

SELECT ads_v2.upsert_ad_group_assets('test-cid', 'a0000000-0000-0000-0000-000000000001',
  '[{"asset": {"id": "1"}, "adGroup": {"id": "1"}, "adGroupAsset": {"fieldType": "SITELINK"}}]'::jsonb);
SELECT is((SELECT count(*)::int FROM ads_v2.ad_group_assets), 1, 'upsert_ad_group_assets works');

SELECT ads_v2.upsert_ad_group_ad_asset_view('test-cid', 'a0000000-0000-0000-0000-000000000001',
  '[{"asset": {"id": "1"}, "adGroup": {"id": "1"}, "adGroupAd": {"ad": {"id": "1"}}, "adGroupAdAssetView": {"fieldType": "HEADLINE"}}]'::jsonb);
SELECT is((SELECT count(*)::int FROM ads_v2.ad_group_ad_asset_view), 1, 'upsert_ad_group_ad_asset_view works');

SELECT * FROM finish();
ROLLBACK;
```

- [ ] **Step 2: Write all RPC functions**

Every function follows the same pattern — extract PK from JSONB, store entire row in `data`, UPSERT:

```sql
-- accounts
CREATE OR REPLACE FUNCTION ads_v2.upsert_accounts(p_customer_id text, p_sync_id text, p_rows jsonb)
RETURNS void AS $$
BEGIN
  INSERT INTO ads_v2.accounts (customer_id, data, last_sync_id, last_checked_at)
  SELECT p_customer_id, r, p_sync_id::uuid, now()
  FROM jsonb_array_elements(p_rows) AS r
  ON CONFLICT (customer_id) DO UPDATE SET
    data = EXCLUDED.data, last_sync_id = EXCLUDED.last_sync_id, last_checked_at = now(), updated_at = now();
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- campaigns
CREATE OR REPLACE FUNCTION ads_v2.upsert_campaigns(p_customer_id text, p_sync_id text, p_rows jsonb)
RETURNS void AS $$
BEGIN
  INSERT INTO ads_v2.campaigns (campaign_id, customer_id, data, last_sync_id, last_checked_at)
  SELECT (r->'campaign'->>'id')::bigint, p_customer_id, r, p_sync_id::uuid, now()
  FROM jsonb_array_elements(p_rows) AS r
  ON CONFLICT (campaign_id, customer_id) DO UPDATE SET
    data = EXCLUDED.data, last_sync_id = EXCLUDED.last_sync_id, last_checked_at = now(), updated_at = now();
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ad_groups
CREATE OR REPLACE FUNCTION ads_v2.upsert_ad_groups(p_customer_id text, p_sync_id text, p_rows jsonb)
RETURNS void AS $$
BEGIN
  INSERT INTO ads_v2.ad_groups (ad_group_id, customer_id, data, last_sync_id, last_checked_at)
  SELECT (r->'adGroup'->>'id')::bigint, p_customer_id, r, p_sync_id::uuid, now()
  FROM jsonb_array_elements(p_rows) AS r
  ON CONFLICT (ad_group_id, customer_id) DO UPDATE SET
    data = EXCLUDED.data, last_sync_id = EXCLUDED.last_sync_id, last_checked_at = now(), updated_at = now();
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ads
CREATE OR REPLACE FUNCTION ads_v2.upsert_ads(p_customer_id text, p_sync_id text, p_rows jsonb)
RETURNS void AS $$
BEGIN
  INSERT INTO ads_v2.ads (ad_id, customer_id, data, last_sync_id, last_checked_at)
  SELECT (r->'adGroupAd'->'ad'->>'id')::bigint, p_customer_id, r, p_sync_id::uuid, now()
  FROM jsonb_array_elements(p_rows) AS r
  ON CONFLICT (ad_id, customer_id) DO UPDATE SET
    data = EXCLUDED.data, last_sync_id = EXCLUDED.last_sync_id, last_checked_at = now(), updated_at = now();
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- assets
CREATE OR REPLACE FUNCTION ads_v2.upsert_assets(p_customer_id text, p_sync_id text, p_rows jsonb)
RETURNS void AS $$
BEGIN
  INSERT INTO ads_v2.assets (asset_id, customer_id, data, last_sync_id, last_checked_at)
  SELECT (r->'asset'->>'id')::bigint, p_customer_id, r, p_sync_id::uuid, now()
  FROM jsonb_array_elements(p_rows) AS r
  ON CONFLICT (asset_id, customer_id) DO UPDATE SET
    data = EXCLUDED.data, last_sync_id = EXCLUDED.last_sync_id, last_checked_at = now(), updated_at = now();
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- customer_assets
CREATE OR REPLACE FUNCTION ads_v2.upsert_customer_assets(p_customer_id text, p_sync_id text, p_rows jsonb)
RETURNS void AS $$
BEGIN
  INSERT INTO ads_v2.customer_assets (customer_id, asset_id, field_type, data, last_sync_id, last_checked_at)
  SELECT p_customer_id, (r->'asset'->>'id')::bigint, r->'customerAsset'->>'fieldType', r, p_sync_id::uuid, now()
  FROM jsonb_array_elements(p_rows) AS r
  ON CONFLICT (customer_id, asset_id, field_type) DO UPDATE SET
    data = EXCLUDED.data, last_sync_id = EXCLUDED.last_sync_id, last_checked_at = now(), updated_at = now();
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- campaign_assets
CREATE OR REPLACE FUNCTION ads_v2.upsert_campaign_assets(p_customer_id text, p_sync_id text, p_rows jsonb)
RETURNS void AS $$
BEGIN
  INSERT INTO ads_v2.campaign_assets (customer_id, campaign_id, asset_id, field_type, data, last_sync_id, last_checked_at)
  SELECT p_customer_id, (r->'campaign'->>'id')::bigint, (r->'asset'->>'id')::bigint, r->'campaignAsset'->>'fieldType', r, p_sync_id::uuid, now()
  FROM jsonb_array_elements(p_rows) AS r
  ON CONFLICT (customer_id, campaign_id, asset_id, field_type) DO UPDATE SET
    data = EXCLUDED.data, last_sync_id = EXCLUDED.last_sync_id, last_checked_at = now(), updated_at = now();
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ad_group_assets
CREATE OR REPLACE FUNCTION ads_v2.upsert_ad_group_assets(p_customer_id text, p_sync_id text, p_rows jsonb)
RETURNS void AS $$
BEGIN
  INSERT INTO ads_v2.ad_group_assets (customer_id, ad_group_id, asset_id, field_type, data, last_sync_id, last_checked_at)
  SELECT p_customer_id, (r->'adGroup'->>'id')::bigint, (r->'asset'->>'id')::bigint, r->'adGroupAsset'->>'fieldType', r, p_sync_id::uuid, now()
  FROM jsonb_array_elements(p_rows) AS r
  ON CONFLICT (customer_id, ad_group_id, asset_id, field_type) DO UPDATE SET
    data = EXCLUDED.data, last_sync_id = EXCLUDED.last_sync_id, last_checked_at = now(), updated_at = now();
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ad_group_ad_asset_view
CREATE OR REPLACE FUNCTION ads_v2.upsert_ad_group_ad_asset_view(p_customer_id text, p_sync_id text, p_rows jsonb)
RETURNS void AS $$
BEGIN
  INSERT INTO ads_v2.ad_group_ad_asset_view (customer_id, ad_group_id, ad_id, asset_id, field_type, data, last_sync_id, last_checked_at)
  SELECT p_customer_id, (r->'adGroup'->>'id')::bigint, (r->'adGroupAd'->'ad'->>'id')::bigint, (r->'asset'->>'id')::bigint, r->'adGroupAdAssetView'->>'fieldType', r, p_sync_id::uuid, now()
  FROM jsonb_array_elements(p_rows) AS r
  ON CONFLICT (customer_id, ad_group_id, ad_id, asset_id, field_type) DO UPDATE SET
    data = EXCLUDED.data, last_sync_id = EXCLUDED.last_sync_id, last_checked_at = now(), updated_at = now();
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- create_sync_run
CREATE OR REPLACE FUNCTION ads_v2.create_sync_run(p_sync_id text, p_customer_id text)
RETURNS void AS $$
BEGIN
  INSERT INTO ads_v2.sync_runs (id, customer_id)
  VALUES (p_sync_id::uuid, p_customer_id)
  ON CONFLICT (id) DO NOTHING;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- finalize_sync
CREATE OR REPLACE FUNCTION ads_v2.finalize_sync(p_customer_id text, p_sync_id text)
RETURNS void AS $$
BEGIN
  UPDATE ads_v2.sync_runs
  SET status = 'completed', completed_at = now()
  WHERE id = p_sync_id::uuid;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
```

- [ ] **Step 3: Apply and test locally**

```bash
supabase db reset && supabase test db
```

- [ ] **Step 4: Commit and push**

---

### Task 3: Create the v2 Edge Function

**Files:**
- Create: `supabase/functions/ingest-gads-v2/index.ts`

- [ ] **Step 1: Create the Edge Function**

```bash
supabase functions new ingest-gads-v2
```

- [ ] **Step 2: Write the function**

Same as v1 but routes to `ads_v2` schema. Resource type maps directly to function name (no `asset_links` remapping needed — each asset link type has its own table and function).

```typescript
import "jsr:@supabase/functions-js/edge-runtime.d.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"

const INGEST_API_KEY = Deno.env.get("INGEST_API_KEY") || ""

Deno.serve(async (req) => {
  if (req.method !== "POST") return new Response("Method not allowed", { status: 405 })

  const apiKey = req.headers.get("x-api-key")
  if (INGEST_API_KEY && apiKey !== INGEST_API_KEY) return new Response("Forbidden", { status: 403 })

  let payload: Record<string, unknown>
  try { payload = await req.json() }
  catch { return new Response("Invalid JSON", { status: 400 }) }

  const syncId = payload.sync_id as string
  const customerId = payload.customer_id as string
  const resourceType = payload.resource_type as string
  const rows = payload.rows as unknown[]

  if (!syncId || !customerId || !resourceType) return new Response("Missing required fields", { status: 400 })

  const supabase = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!)

  const rpcMap: Record<string, string> = {
    accounts: "upsert_accounts",
    campaigns: "upsert_campaigns",
    ad_groups: "upsert_ad_groups",
    ads: "upsert_ads",
    assets: "upsert_assets",
    customer_assets: "upsert_customer_assets",
    campaign_assets: "upsert_campaign_assets",
    ad_group_assets: "upsert_ad_group_assets",
    ad_group_ad_asset_view: "upsert_ad_group_ad_asset_view",
    create_sync_run: "create_sync_run",
    finalize: "finalize_sync",
  }

  const rpcName = rpcMap[resourceType]
  if (!rpcName) return new Response(`Unknown: ${resourceType}`, { status: 400 })

  const params = (resourceType === "create_sync_run")
    ? { p_sync_id: syncId, p_customer_id: customerId }
    : (resourceType === "finalize")
    ? { p_customer_id: customerId, p_sync_id: syncId }
    : { p_customer_id: customerId, p_sync_id: syncId, p_rows: rows }

  const { error } = await supabase.schema("ads_v2").rpc(rpcName, params)
  if (error) {
    console.error(`${rpcName} failed:`, error)
    return new Response(JSON.stringify({ error: error.message }), { status: 500 })
  }

  return new Response(JSON.stringify({ ok: true, count: rows?.length ?? 0 }), { status: 200 })
})
```

- [ ] **Step 3: Set secrets for preview branch**

```bash
supabase secrets set --env-file supabase/functions/ingest-gads-v2/.env --project-ref makglpeikfgyugngywmc
```

- [ ] **Step 4: Commit and push**

---

### Task 4: Create the v2 Google Ads Script

**Files:**
- Create: `scripts/ad-asset-policy-monitor-v2/main.js`

- [ ] **Step 1: Write the script**

Key differences from v1:
- GAQL queries pull EVERY field (from the spec)
- No transformers — raw row objects sent directly
- Resource types map 1:1 to table names (no `asset_links` remapping)
- Points to `ingest-gads-v2` Edge Function

The script is straightforward: QUERIES object + pullResource_ + pushToSupabase_ + main(). No TRANSFORMERS object.

- [ ] **Step 2: Commit and push**

---

### Task 5: Deploy and test with real data

- [ ] **Step 1: Wait for preview branch to apply migrations**
- [ ] **Step 2: Paste v2 script into Google Ads, run manually**
- [ ] **Step 3: Check Supabase Studio — verify all 9 tables have data**
- [ ] **Step 4: Compare v1 and v2 data side by side**

---

## Definition of Done

- [ ] `ads_v2` schema exists with 9 data tables + sync_runs
- [ ] 9 RPC upsert functions extract PKs from JSONB and store raw data
- [ ] Edge Function routes to correct RPC, validates API key
- [ ] Google Ads Script pulls every available field, sends raw objects
- [ ] Real Google Ads data lands in all 9 tables
- [ ] v1 tables are untouched and still functional
- [ ] All pgTAP tests pass
