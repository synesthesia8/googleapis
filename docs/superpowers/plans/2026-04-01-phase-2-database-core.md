# Phase 2: Database Core (Walking Skeleton)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Create the full database schema (hierarchy tables, asset_links, status_changes), change detection triggers, and cascade materialized view. Prove it all works with fake data and pgTAP tests before any application code exists.

**Architecture:** Typed relational tables modeling the Google Ads hierarchy (campaigns → ad_groups → ads → assets → asset_links). UPSERT + triggers for change detection. Materialized view for cascade impact.

**Tech Stack:** Postgres 15+, pgTAP, Supabase CLI

**Depends on:** Phase 1 (ads schema, pgTAP enabled)

**Spec reference:** `docs/superpowers/specs/2026-04-01-google-ads-asset-policy-monitor-design.md` — Database Schema section

---

### Task 1: Create dimension tables (accounts, campaigns, ad_groups, ads, assets)

**Files:**
- Create: `supabase/migrations/00003_create_dimension_tables.sql`
- Create: `supabase/tests/00002_dimension_tables.sql`

- [ ] **Step 1: Write the test**

```sql
-- supabase/tests/00002_dimension_tables.sql
BEGIN;
SELECT plan(10);

SELECT has_table('ads', 'accounts', 'accounts table should exist');
SELECT has_table('ads', 'campaigns', 'campaigns table should exist');
SELECT has_table('ads', 'ad_groups', 'ad_groups table should exist');
SELECT has_table('ads', 'ads', 'ads table should exist');
SELECT has_table('ads', 'assets', 'assets table should exist');

-- Check PKs
SELECT has_pk('ads', 'accounts', 'accounts should have a PK');
SELECT has_pk('ads', 'campaigns', 'campaigns should have a PK');
SELECT has_pk('ads', 'ad_groups', 'ad_groups should have a PK');
SELECT has_pk('ads', 'ads', 'ads should have a PK');
SELECT has_pk('ads', 'assets', 'assets should have a PK');

SELECT * FROM finish();
ROLLBACK;
```

- [ ] **Step 2: Run test to verify it fails**

```bash
supabase test db
```

Expected: FAIL — tables don't exist yet.

- [ ] **Step 3: Write the migration**

```sql
-- supabase/migrations/00003_create_dimension_tables.sql

CREATE TABLE ads.accounts (
  customer_id       text PRIMARY KEY,
  descriptive_name  text,
  currency_code     text,
  time_zone         text,
  is_mcc            boolean,
  mcc_customer_id   text,
  status            text,
  created_at        timestamptz NOT NULL DEFAULT now(),
  updated_at        timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE ads.campaigns (
  campaign_id         bigint NOT NULL,
  customer_id         text NOT NULL REFERENCES ads.accounts(customer_id),
  name                text,
  status              text,
  serving_status      text,
  channel_type        text,
  channel_sub_type    text,
  bidding_strategy    text,
  start_date          date,
  end_date            date,
  budget_amount_micros bigint,
  last_checked_at     timestamptz,
  created_at          timestamptz NOT NULL DEFAULT now(),
  updated_at          timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (campaign_id, customer_id)
);

CREATE TABLE ads.ad_groups (
  ad_group_id       bigint NOT NULL,
  customer_id       text NOT NULL,
  campaign_id       bigint NOT NULL,
  name              text,
  status            text,
  type              text,
  cpc_bid_micros    bigint,
  last_checked_at   timestamptz,
  created_at        timestamptz NOT NULL DEFAULT now(),
  updated_at        timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (ad_group_id, customer_id),
  FOREIGN KEY (campaign_id, customer_id) REFERENCES ads.campaigns(campaign_id, customer_id)
);

CREATE TABLE ads.ads (
  ad_id             bigint NOT NULL,
  customer_id       text NOT NULL,
  ad_group_id       bigint NOT NULL,
  ad_type           text,
  status            text,
  approval_status   text,
  review_status     text,
  ad_strength       text,
  policy_topics     jsonb,
  final_urls        text[],
  last_checked_at   timestamptz,
  created_at        timestamptz NOT NULL DEFAULT now(),
  updated_at        timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (ad_id, customer_id),
  FOREIGN KEY (ad_group_id, customer_id) REFERENCES ads.ad_groups(ad_group_id, customer_id)
);

CREATE TABLE ads.assets (
  asset_id            bigint NOT NULL,
  customer_id         text NOT NULL,
  name                text,
  asset_type          text NOT NULL,
  text_content        text,
  image_url           text,
  image_width         int,
  image_height        int,
  youtube_video_id    text,
  sitelink_text       text,
  sitelink_desc1      text,
  sitelink_desc2      text,
  callout_text        text,
  snippet_header      text,
  snippet_values      text[],
  phone_number        text,
  global_approval     text,
  global_review       text,
  global_policy_topics jsonb,
  last_checked_at     timestamptz,
  created_at          timestamptz NOT NULL DEFAULT now(),
  updated_at          timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (asset_id, customer_id)
);
```

- [ ] **Step 4: Apply and run tests**

```bash
supabase db reset && supabase test db
```

Expected: All 10 tests pass.

- [ ] **Step 5: Commit**

```bash
git add supabase/migrations/ supabase/tests/
git commit -m "feat: create dimension tables (accounts, campaigns, ad_groups, ads, assets)"
```

---

### Task 2: Create asset_links fact table

**Files:**
- Create: `supabase/migrations/00004_create_asset_links.sql`
- Create: `supabase/tests/00003_asset_links.sql`

- [ ] **Step 1: Write the test**

```sql
-- supabase/tests/00003_asset_links.sql
BEGIN;
SELECT plan(3);

SELECT has_table('ads', 'asset_links', 'asset_links table should exist');
SELECT has_pk('ads', 'asset_links', 'asset_links should have a PK');
SELECT has_index('ads', 'asset_links', 'idx_asset_links_natural_key', 'natural key unique index should exist');

SELECT * FROM finish();
ROLLBACK;
```

- [ ] **Step 2: Run test to verify it fails**

```bash
supabase test db
```

- [ ] **Step 3: Write the migration**

```sql
-- supabase/migrations/00004_create_asset_links.sql

CREATE TABLE ads.asset_links (
  id                  bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  customer_id         text NOT NULL,
  link_level          text NOT NULL,
  asset_id            bigint NOT NULL,
  field_type          text NOT NULL,
  campaign_id         bigint,
  ad_group_id         bigint,
  ad_id               bigint,
  link_status         text,
  approval_status     text NOT NULL,
  review_status       text,
  primary_status      text,
  primary_status_reasons text[],
  policy_topics       jsonb,
  is_enabled          boolean,
  performance_label   text,
  pinned_field        text,
  asset_source        text,
  last_sync_id        uuid,
  last_checked_at     timestamptz,
  first_seen_at       timestamptz NOT NULL DEFAULT now(),
  updated_at          timestamptz NOT NULL DEFAULT now(),

  CONSTRAINT valid_link_level CHECK (link_level IN ('CUSTOMER', 'CAMPAIGN', 'AD_GROUP', 'AD'))
);

-- Natural key for UPSERT conflict target
CREATE UNIQUE INDEX idx_asset_links_natural_key
  ON ads.asset_links (
    customer_id, link_level, asset_id, field_type,
    COALESCE(campaign_id, 0), COALESCE(ad_group_id, 0), COALESCE(ad_id, 0)
  );

-- Disapproved assets (the main query)
CREATE INDEX idx_asset_links_disapproved
  ON ads.asset_links (customer_id, approval_status)
  WHERE approval_status != 'APPROVED';

-- Navigate the hierarchy
CREATE INDEX idx_asset_links_hierarchy
  ON ads.asset_links (customer_id, campaign_id, ad_group_id, ad_id);

-- All links for a specific asset
CREATE INDEX idx_asset_links_asset
  ON ads.asset_links (customer_id, asset_id);

-- Deletion detection
CREATE INDEX idx_asset_links_sync
  ON ads.asset_links (customer_id, last_sync_id);
```

- [ ] **Step 4: Apply and run tests**

```bash
supabase db reset && supabase test db
```

Expected: All tests pass.

- [ ] **Step 5: Commit**

```bash
git add supabase/migrations/ supabase/tests/
git commit -m "feat: create asset_links fact table with natural key index"
```

---

### Task 3: Create status_changes table and sync_runs table

**Files:**
- Create: `supabase/migrations/00005_create_status_changes_and_sync_runs.sql`
- Create: `supabase/tests/00004_status_changes.sql`

- [ ] **Step 1: Write the test**

```sql
-- supabase/tests/00004_status_changes.sql
BEGIN;
SELECT plan(4);

SELECT has_table('ads', 'status_changes', 'status_changes table should exist');
SELECT has_table('ads', 'sync_runs', 'sync_runs table should exist');
SELECT has_index('ads', 'status_changes', 'idx_changes_lookup', 'changes lookup index should exist');
SELECT has_index('ads', 'status_changes', 'idx_changes_entity', 'changes entity index should exist');

SELECT * FROM finish();
ROLLBACK;
```

- [ ] **Step 2: Run test to verify it fails**

```bash
supabase test db
```

- [ ] **Step 3: Write the migration**

```sql
-- supabase/migrations/00005_create_status_changes_and_sync_runs.sql

CREATE TABLE ads.status_changes (
  id            bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  customer_id   text NOT NULL,
  entity_type   text NOT NULL,
  entity_id     bigint NOT NULL,
  field_name    text NOT NULL,
  old_value     text,
  new_value     text,
  changed_at    timestamptz NOT NULL DEFAULT now(),

  CONSTRAINT valid_entity_type CHECK (entity_type IN ('ASSET_LINK', 'AD', 'AD_GROUP', 'CAMPAIGN'))
);

CREATE INDEX idx_changes_lookup
  ON ads.status_changes (customer_id, entity_type, changed_at DESC);
CREATE INDEX idx_changes_entity
  ON ads.status_changes (entity_id, changed_at DESC);

CREATE TABLE ads.sync_runs (
  id                    uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  customer_id           text NOT NULL,
  started_at            timestamptz NOT NULL DEFAULT now(),
  completed_at          timestamptz,
  status                text NOT NULL DEFAULT 'running',
  is_first_sync         boolean NOT NULL DEFAULT false,
  rows_by_type          jsonb,
  truncation_warnings   text[],
  error                 text,

  CONSTRAINT valid_sync_status CHECK (status IN ('running', 'completed', 'failed'))
);
```

- [ ] **Step 4: Apply and run tests**

```bash
supabase db reset && supabase test db
```

Expected: All tests pass.

- [ ] **Step 5: Commit**

```bash
git add supabase/migrations/ supabase/tests/
git commit -m "feat: create status_changes and sync_runs tables"
```

---

### Task 4: Create change detection triggers

**Files:**
- Create: `supabase/migrations/00006_create_change_triggers.sql`
- Create: `supabase/tests/00005_triggers.sql`

- [ ] **Step 1: Write the test**

```sql
-- supabase/tests/00005_triggers.sql
BEGIN;
SELECT plan(7);

-- Seed test data
INSERT INTO ads.accounts (customer_id, descriptive_name) VALUES ('test-cid', 'Test Account');
INSERT INTO ads.campaigns (campaign_id, customer_id, name, status, serving_status)
  VALUES (1, 'test-cid', 'Test Campaign', 'ENABLED', 'SERVING');
INSERT INTO ads.ad_groups (ad_group_id, customer_id, campaign_id, name, status)
  VALUES (1, 'test-cid', 1, 'Test Ad Group', 'ENABLED');
INSERT INTO ads.ads (ad_id, customer_id, ad_group_id, status, approval_status)
  VALUES (1, 'test-cid', 1, 'ENABLED', 'APPROVED');
INSERT INTO ads.assets (asset_id, customer_id, asset_type, text_content, global_approval)
  VALUES (1, 'test-cid', 'TEXT', 'Buy cheap meds now', 'APPROVED');
INSERT INTO ads.asset_links (customer_id, link_level, asset_id, field_type, campaign_id, ad_group_id, ad_id, approval_status, link_status)
  VALUES ('test-cid', 'AD', 1, 'HEADLINE', 1, 1, 1, 'APPROVED', 'ENABLED');

-- Test 1: No changes logged yet
SELECT is(
  (SELECT count(*)::int FROM ads.status_changes),
  0,
  'No status changes should exist before any updates'
);

-- Test 2: Update asset_link approval_status → should trigger
UPDATE ads.asset_links SET approval_status = 'DISAPPROVED' WHERE id = 1;

SELECT is(
  (SELECT count(*)::int FROM ads.status_changes WHERE entity_type = 'ASSET_LINK'),
  1,
  'One status change should be logged for asset_link approval_status change'
);

SELECT is(
  (SELECT old_value FROM ads.status_changes WHERE entity_type = 'ASSET_LINK' AND field_name = 'approval_status' LIMIT 1),
  'APPROVED',
  'Old value should be APPROVED'
);

SELECT is(
  (SELECT new_value FROM ads.status_changes WHERE entity_type = 'ASSET_LINK' AND field_name = 'approval_status' LIMIT 1),
  'DISAPPROVED',
  'New value should be DISAPPROVED'
);

-- Test 3: Update ad approval_status → should trigger
UPDATE ads.ads SET approval_status = 'DISAPPROVED' WHERE ad_id = 1 AND customer_id = 'test-cid';

SELECT is(
  (SELECT count(*)::int FROM ads.status_changes WHERE entity_type = 'AD'),
  1,
  'One status change should be logged for ad approval_status change'
);

-- Test 4: Update campaign serving_status → should trigger
UPDATE ads.campaigns SET serving_status = 'NONE' WHERE campaign_id = 1 AND customer_id = 'test-cid';

SELECT is(
  (SELECT count(*)::int FROM ads.status_changes WHERE entity_type = 'CAMPAIGN'),
  1,
  'One status change should be logged for campaign serving_status change'
);

-- Test 5: Update a non-tracked field → should NOT trigger
UPDATE ads.asset_links SET performance_label = 'BEST' WHERE id = 1;

SELECT is(
  (SELECT count(*)::int FROM ads.status_changes),
  3,
  'No new status change should be logged for non-tracked field update'
);

SELECT * FROM finish();
ROLLBACK;
```

- [ ] **Step 2: Run test to verify it fails**

```bash
supabase test db
```

Expected: FAIL — triggers don't exist yet.

- [ ] **Step 3: Write the migration**

```sql
-- supabase/migrations/00006_create_change_triggers.sql

-- ── ASSET LINK trigger ───────────────────────────────────────────
CREATE OR REPLACE FUNCTION ads.track_asset_link_changes()
RETURNS trigger AS $$
BEGIN
  IF OLD.approval_status IS DISTINCT FROM NEW.approval_status THEN
    INSERT INTO ads.status_changes (customer_id, entity_type, entity_id, field_name, old_value, new_value)
    VALUES (NEW.customer_id, 'ASSET_LINK', NEW.id, 'approval_status', OLD.approval_status, NEW.approval_status);
  END IF;
  IF OLD.review_status IS DISTINCT FROM NEW.review_status THEN
    INSERT INTO ads.status_changes (customer_id, entity_type, entity_id, field_name, old_value, new_value)
    VALUES (NEW.customer_id, 'ASSET_LINK', NEW.id, 'review_status', OLD.review_status, NEW.review_status);
  END IF;
  IF OLD.primary_status IS DISTINCT FROM NEW.primary_status THEN
    INSERT INTO ads.status_changes (customer_id, entity_type, entity_id, field_name, old_value, new_value)
    VALUES (NEW.customer_id, 'ASSET_LINK', NEW.id, 'primary_status', OLD.primary_status, NEW.primary_status);
  END IF;
  IF OLD.link_status IS DISTINCT FROM NEW.link_status THEN
    INSERT INTO ads.status_changes (customer_id, entity_type, entity_id, field_name, old_value, new_value)
    VALUES (NEW.customer_id, 'ASSET_LINK', NEW.id, 'link_status', OLD.link_status, NEW.link_status);
  END IF;
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_asset_link_changes
  BEFORE UPDATE ON ads.asset_links
  FOR EACH ROW EXECUTE FUNCTION ads.track_asset_link_changes();

-- ── AD trigger ───────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION ads.track_ad_changes()
RETURNS trigger AS $$
BEGIN
  IF OLD.approval_status IS DISTINCT FROM NEW.approval_status THEN
    INSERT INTO ads.status_changes (customer_id, entity_type, entity_id, field_name, old_value, new_value)
    VALUES (NEW.customer_id, 'AD', NEW.ad_id, 'approval_status', OLD.approval_status, NEW.approval_status);
  END IF;
  IF OLD.review_status IS DISTINCT FROM NEW.review_status THEN
    INSERT INTO ads.status_changes (customer_id, entity_type, entity_id, field_name, old_value, new_value)
    VALUES (NEW.customer_id, 'AD', NEW.ad_id, 'review_status', OLD.review_status, NEW.review_status);
  END IF;
  IF OLD.status IS DISTINCT FROM NEW.status THEN
    INSERT INTO ads.status_changes (customer_id, entity_type, entity_id, field_name, old_value, new_value)
    VALUES (NEW.customer_id, 'AD', NEW.ad_id, 'status', OLD.status, NEW.status);
  END IF;
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_ad_changes
  BEFORE UPDATE ON ads.ads
  FOR EACH ROW EXECUTE FUNCTION ads.track_ad_changes();

-- ── AD GROUP trigger ─────────────────────────────────────────────
CREATE OR REPLACE FUNCTION ads.track_ad_group_changes()
RETURNS trigger AS $$
BEGIN
  IF OLD.status IS DISTINCT FROM NEW.status THEN
    INSERT INTO ads.status_changes (customer_id, entity_type, entity_id, field_name, old_value, new_value)
    VALUES (NEW.customer_id, 'AD_GROUP', NEW.ad_group_id, 'status', OLD.status, NEW.status);
  END IF;
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_ad_group_changes
  BEFORE UPDATE ON ads.ad_groups
  FOR EACH ROW EXECUTE FUNCTION ads.track_ad_group_changes();

-- ── CAMPAIGN trigger ─────────────────────────────────────────────
CREATE OR REPLACE FUNCTION ads.track_campaign_changes()
RETURNS trigger AS $$
BEGIN
  IF OLD.status IS DISTINCT FROM NEW.status THEN
    INSERT INTO ads.status_changes (customer_id, entity_type, entity_id, field_name, old_value, new_value)
    VALUES (NEW.customer_id, 'CAMPAIGN', NEW.campaign_id, 'status', OLD.status, NEW.status);
  END IF;
  IF OLD.serving_status IS DISTINCT FROM NEW.serving_status THEN
    INSERT INTO ads.status_changes (customer_id, entity_type, entity_id, field_name, old_value, new_value)
    VALUES (NEW.customer_id, 'CAMPAIGN', NEW.campaign_id, 'serving_status', OLD.serving_status, NEW.serving_status);
  END IF;
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_campaign_changes
  BEFORE UPDATE ON ads.campaigns
  FOR EACH ROW EXECUTE FUNCTION ads.track_campaign_changes();
```

- [ ] **Step 4: Apply and run tests**

```bash
supabase db reset && supabase test db
```

Expected: All 7 trigger tests pass.

- [ ] **Step 5: Commit**

```bash
git add supabase/migrations/ supabase/tests/
git commit -m "feat: add change detection triggers for all hierarchy tables"
```

---

### Task 5: Create the cascade materialized view

**Files:**
- Create: `supabase/migrations/00007_create_cascade_view.sql`
- Create: `supabase/tests/00006_cascade_view.sql`

- [ ] **Step 1: Write the test**

```sql
-- supabase/tests/00006_cascade_view.sql
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

-- Also insert an APPROVED asset link (different asset, same ad) to test ASSET_ONLY
INSERT INTO ads.assets (asset_id, customer_id, asset_type, text_content, global_approval)
  VALUES (2, 'test-cid', 'TEXT', 'Great deals here', 'APPROVED');
INSERT INTO ads.asset_links (customer_id, link_level, asset_id, field_type, campaign_id, ad_group_id, ad_id, approval_status, link_status, last_checked_at)
  VALUES ('test-cid', 'AD', 2, 'HEADLINE', 1, 1, 1, 'APPROVED', 'ENABLED', now());

-- Refresh the materialized view
REFRESH MATERIALIZED VIEW ads.cascade_status;

-- Test 1: View should have exactly 1 row (only non-approved)
SELECT is(
  (SELECT count(*)::int FROM ads.cascade_status),
  1,
  'Cascade view should only show non-approved asset links'
);

-- Test 2: Should show the correct asset content
SELECT is(
  (SELECT text_content FROM ads.cascade_status LIMIT 1),
  'Buy cheap meds now',
  'Should show the asset text content'
);

-- Test 3: Should show ad is DISAPPROVED
SELECT is(
  (SELECT ad_approval FROM ads.cascade_status LIMIT 1),
  'DISAPPROVED',
  'Should show ad approval status'
);

-- Test 4: Should show campaign is still SERVING
SELECT is(
  (SELECT campaign_serving FROM ads.cascade_status LIMIT 1),
  'SERVING',
  'Should show campaign serving status'
);

-- Test 5: Impact level should be AD_KILLED (ad is disapproved)
SELECT is(
  (SELECT impact_level FROM ads.cascade_status LIMIT 1),
  'AD_KILLED',
  'Impact level should be AD_KILLED when ad is disapproved'
);

SELECT * FROM finish();
ROLLBACK;
```

- [ ] **Step 2: Run test to verify it fails**

```bash
supabase test db
```

- [ ] **Step 3: Write the migration**

```sql
-- supabase/migrations/00007_create_cascade_view.sql

CREATE MATERIALIZED VIEW ads.cascade_status AS
SELECT
  al.id               AS asset_link_id,
  al.customer_id,
  al.link_level,
  al.asset_id,
  al.field_type,

  -- The asset itself
  a.asset_type,
  a.text_content,
  a.image_url,
  a.sitelink_text,
  a.callout_text,
  a.youtube_video_id,
  a.phone_number,
  al.approval_status   AS asset_link_approval,
  al.review_status     AS asset_link_review,
  al.primary_status,
  al.policy_topics,
  a.global_approval    AS asset_global_approval,

  -- The ad (null for non-AD link levels)
  ad.ad_id,
  ad.ad_type,
  ad.status            AS ad_status,
  ad.approval_status   AS ad_approval,
  ad.ad_strength,

  -- The ad group
  ag.ad_group_id,
  ag.name              AS ad_group_name,
  ag.status            AS ad_group_status,

  -- The campaign
  c.campaign_id,
  c.name               AS campaign_name,
  c.status             AS campaign_status,
  c.serving_status     AS campaign_serving,
  c.channel_type,

  -- Impact assessment
  CASE
    WHEN al.approval_status = 'DISAPPROVED'
      AND ad.approval_status = 'DISAPPROVED' THEN 'AD_KILLED'
    WHEN al.approval_status = 'DISAPPROVED'
      AND (ad.approval_status IS NULL OR ad.approval_status != 'DISAPPROVED') THEN 'ASSET_ONLY'
    WHEN al.approval_status = 'APPROVED_LIMITED' THEN 'LIMITED_REACH'
    WHEN al.approval_status = 'AREA_OF_INTEREST_ONLY' THEN 'GEO_RESTRICTED'
    ELSE 'OTHER'
  END AS impact_level,

  -- Freshness
  CASE
    WHEN al.last_checked_at > now() - interval '2 hours' THEN 'FRESH'
    WHEN al.last_checked_at > now() - interval '6 hours' THEN 'STALE'
    ELSE 'UNKNOWN'
  END AS freshness,

  al.last_checked_at

FROM ads.asset_links al
JOIN ads.assets a
  ON al.asset_id = a.asset_id AND al.customer_id = a.customer_id
LEFT JOIN ads.ads ad
  ON al.ad_id = ad.ad_id AND al.customer_id = ad.customer_id
LEFT JOIN ads.ad_groups ag
  ON al.ad_group_id = ag.ad_group_id AND al.customer_id = ag.customer_id
LEFT JOIN ads.campaigns c
  ON al.campaign_id = c.campaign_id AND al.customer_id = c.customer_id
WHERE al.approval_status != 'APPROVED'
  AND al.link_status != 'REMOVED';

-- Unique index required for REFRESH CONCURRENTLY
CREATE UNIQUE INDEX idx_cascade_status_pk ON ads.cascade_status (asset_link_id);

-- Index for common queries
CREATE INDEX idx_cascade_status_customer ON ads.cascade_status (customer_id);
CREATE INDEX idx_cascade_status_impact ON ads.cascade_status (impact_level);
```

- [ ] **Step 4: Apply and run tests**

```bash
supabase db reset && supabase test db
```

Expected: All cascade view tests pass.

- [ ] **Step 5: Commit**

```bash
git add supabase/migrations/ supabase/tests/
git commit -m "feat: create cascade_status materialized view with impact_level and freshness"
```

---

### Task 6: Seed realistic test data and verify manually

**Files:**
- Create: `supabase/seed.sql`

- [ ] **Step 1: Write the seed data**

```sql
-- supabase/seed.sql
-- Realistic scenario: 1 account, 2 campaigns, multiple ads with mixed approval states

-- Account
INSERT INTO ads.accounts (customer_id, descriptive_name, currency_code, time_zone)
VALUES ('123-456-7890', 'My Test Account', 'AUD', 'Australia/Sydney');

-- Campaigns
INSERT INTO ads.campaigns (campaign_id, customer_id, name, status, serving_status, channel_type)
VALUES
  (100, '123-456-7890', 'Brand Campaign', 'ENABLED', 'SERVING', 'SEARCH'),
  (200, '123-456-7890', 'Competitor Campaign', 'ENABLED', 'SERVING', 'SEARCH');

-- Ad Groups
INSERT INTO ads.ad_groups (ad_group_id, customer_id, campaign_id, name, status)
VALUES
  (10, '123-456-7890', 100, 'Brand — Exact', 'ENABLED'),
  (20, '123-456-7890', 200, 'Competitor — Broad', 'ENABLED');

-- Ads
INSERT INTO ads.ads (ad_id, customer_id, ad_group_id, ad_type, status, approval_status, ad_strength)
VALUES
  (1001, '123-456-7890', 10, 'RESPONSIVE_SEARCH_AD', 'ENABLED', 'APPROVED', 'GOOD'),
  (1002, '123-456-7890', 10, 'RESPONSIVE_SEARCH_AD', 'ENABLED', 'DISAPPROVED', 'POOR'),
  (1003, '123-456-7890', 20, 'RESPONSIVE_SEARCH_AD', 'ENABLED', 'APPROVED', 'EXCELLENT');

-- Assets (the actual content)
INSERT INTO ads.assets (asset_id, customer_id, asset_type, text_content, global_approval)
VALUES
  (5001, '123-456-7890', 'TEXT', 'Official Brand Store', 'APPROVED'),
  (5002, '123-456-7890', 'TEXT', 'Buy Cheap Meds Now', 'DISAPPROVED'),
  (5003, '123-456-7890', 'TEXT', 'Best Prices Guaranteed', 'APPROVED'),
  (5004, '123-456-7890', 'TEXT', 'Free Shipping Today', 'APPROVED'),
  (5005, '123-456-7890', 'TEXT', 'Limited Time Offer', 'APPROVED_LIMITED');

-- Asset Links — Ad level (headlines in RSAs)
INSERT INTO ads.asset_links (customer_id, link_level, asset_id, field_type, campaign_id, ad_group_id, ad_id, approval_status, link_status, last_checked_at)
VALUES
  -- Ad 1001 (approved ad, all headlines fine)
  ('123-456-7890', 'AD', 5001, 'HEADLINE', 100, 10, 1001, 'APPROVED', 'ENABLED', now()),
  ('123-456-7890', 'AD', 5003, 'HEADLINE', 100, 10, 1001, 'APPROVED', 'ENABLED', now()),
  ('123-456-7890', 'AD', 5004, 'HEADLINE', 100, 10, 1001, 'APPROVED', 'ENABLED', now()),

  -- Ad 1002 (disapproved ad, one bad headline)
  ('123-456-7890', 'AD', 5002, 'HEADLINE', 100, 10, 1002, 'DISAPPROVED', 'ENABLED', now()),
  ('123-456-7890', 'AD', 5003, 'HEADLINE', 100, 10, 1002, 'APPROVED', 'ENABLED', now()),

  -- Ad 1003 (approved ad, one limited headline)
  ('123-456-7890', 'AD', 5005, 'HEADLINE', 200, 20, 1003, 'APPROVED_LIMITED', 'ENABLED', now()),
  ('123-456-7890', 'AD', 5004, 'HEADLINE', 200, 20, 1003, 'APPROVED', 'ENABLED', now());

-- Asset Links — Account level (sitelink disapproved)
INSERT INTO ads.assets (asset_id, customer_id, asset_type, sitelink_text, sitelink_desc1, global_approval)
VALUES (5006, '123-456-7890', 'SITELINK', 'Free Trial', 'Start your free trial today', 'DISAPPROVED');

INSERT INTO ads.asset_links (customer_id, link_level, asset_id, field_type, approval_status, link_status, last_checked_at)
VALUES ('123-456-7890', 'CUSTOMER', 5006, 'SITELINK', 'DISAPPROVED', 'ENABLED', now());

-- Refresh the cascade view
REFRESH MATERIALIZED VIEW ads.cascade_status;
```

- [ ] **Step 2: Apply seed data**

```bash
supabase db reset
```

This runs all migrations AND the seed file.

- [ ] **Step 3: Query the cascade view and verify output**

```bash
supabase db execute --sql "
SELECT
  link_level,
  asset_type,
  COALESCE(text_content, sitelink_text) AS content,
  asset_link_approval,
  ad_approval,
  ad_group_name,
  campaign_name,
  campaign_serving,
  impact_level,
  freshness
FROM ads.cascade_status
ORDER BY impact_level, campaign_name;
"
```

Expected output (3 rows):

| link_level | asset_type | content | asset_link_approval | ad_approval | ad_group_name | campaign_name | campaign_serving | impact_level | freshness |
|---|---|---|---|---|---|---|---|---|---|
| AD | TEXT | Buy Cheap Meds Now | DISAPPROVED | DISAPPROVED | Brand — Exact | Brand Campaign | SERVING | AD_KILLED | FRESH |
| CUSTOMER | SITELINK | Free Trial | DISAPPROVED | (null) | (null) | (null) | (null) | ASSET_ONLY | FRESH |
| AD | TEXT | Limited Time Offer | APPROVED_LIMITED | APPROVED | Competitor — Broad | Competitor Campaign | SERVING | LIMITED_REACH | FRESH |

This is the table you sit down and look at on Monday morning.

- [ ] **Step 4: Test a status change — simulate a disapproval resolving**

```bash
supabase db execute --sql "
UPDATE ads.asset_links SET approval_status = 'APPROVED'
WHERE asset_id = 5002 AND customer_id = '123-456-7890';

-- Check the change was logged
SELECT entity_type, field_name, old_value, new_value, changed_at
FROM ads.status_changes ORDER BY changed_at DESC LIMIT 5;
"
```

Expected: One row showing `DISAPPROVED → APPROVED`.

```bash
supabase db execute --sql "
REFRESH MATERIALIZED VIEW ads.cascade_status;
SELECT count(*) FROM ads.cascade_status WHERE impact_level = 'AD_KILLED';
"
```

Expected: `0` — the AD_KILLED row is gone.

- [ ] **Step 5: Commit**

```bash
git add supabase/seed.sql
git commit -m "feat: add realistic seed data for manual verification"
```

---

## Phase 2 Definition of Done

- [ ] All 5 dimension tables exist with correct columns and PKs
- [ ] `asset_links` fact table exists with natural key unique index
- [ ] `status_changes` and `sync_runs` tables exist
- [ ] Change detection triggers fire correctly on all tracked fields
- [ ] Triggers do NOT fire on non-tracked field updates
- [ ] Cascade materialized view shows correct impact_level and freshness
- [ ] Seed data produces the expected cascade output
- [ ] All pgTAP tests pass via `supabase test db`
- [ ] All changes committed as replayable migrations
