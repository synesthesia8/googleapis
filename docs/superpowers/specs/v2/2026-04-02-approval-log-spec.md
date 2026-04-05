# Approval Log — Build Spec

**Decision reference:** `docs/decisions/0001-approval-log-design.md`
**Findings reference:** `docs/sources/google-ads-asset-approval-originates-differently-by-type.md`

## Table

```sql
CREATE TABLE ads_v2.policy_timeline (
  id              bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  changed_at      timestamptz NOT NULL DEFAULT now(),

  -- Identity
  entity_key      text NOT NULL,
  entity_type     text NOT NULL,        -- ASSET_IN_AD, EXTENSION, AD
  customer_id     text NOT NULL,
  asset_id        bigint,               -- null for AD type
  ad_id           bigint,               -- null for EXTENSION type
  field_type      text,                 -- HEADLINE, DESCRIPTION, SITELINK, etc.

  -- Transition
  old_status      text,                 -- null on bootstrap
  new_status      text NOT NULL,

  -- Frozen context
  asset_content   text,                 -- "Travel to Vietnam", "Terms & Conditions"
  asset_type      text,                 -- TEXT, SITELINK, CALLOUT, IMAGE
  campaign_name   text,
  campaign_id     bigint,
  ad_group_name   text,
  ad_group_id     bigint,

  -- Why
  policy_topics   jsonb                 -- [{topic, type}] frozen at time of change
);
```

## Indexes

```sql
CREATE INDEX idx_log_entity ON ads_v2.policy_timeline (entity_key, changed_at);
CREATE INDEX idx_log_time ON ads_v2.policy_timeline (changed_at DESC);
CREATE INDEX idx_log_disapprovals ON ads_v2.policy_timeline (new_status, changed_at DESC)
  WHERE new_status = 'DISAPPROVED';
CREATE INDEX idx_log_customer ON ads_v2.policy_timeline (customer_id, changed_at DESC);
```

## Sync Order Dependency

The Google Ads Script processes resource types sequentially. The triggers on `ad_group_ad_asset_view` need asset content from the `assets` table. The script MUST sync `assets` BEFORE `ad_group_ad_asset_view` to ensure the content is current when the trigger fires.

Required sync order:
1. `accounts`
2. `campaigns`
3. `ad_groups`
4. `ads`
5. `assets` ← must be before asset view
6. `customer_assets`
7. `campaign_assets`
8. `ad_group_assets`
9. `ad_group_ad_asset_view` ← triggers JOIN to assets table

This is already the order in the script's `QUERIES` object, but it must be enforced — never reorder.

## Triggers

### Trigger 1: Asset-in-ad (`ads_v2.ad_group_ad_asset_view`)

**Watches:** `data->'adGroupAdAssetView'->'policySummary'->>'approvalStatus'`

**Fires when:** The approval status value changes between OLD and NEW, OR when it appears for the first time (OLD path is null, NEW path is not null), OR when it disappears (OLD path is not null, NEW path is null).

**On change, logs:**

| Field | Source |
|---|---|
| `entity_type` | `'ASSET_IN_AD'` |
| `entity_key` | `'ASSET_IN_AD:' \|\| customer_id \|\| ':' \|\| asset_id \|\| ':' \|\| ad_id \|\| ':' \|\| field_type` |
| `asset_id` | `NEW.asset_id` (typed PK column) |
| `ad_id` | `NEW.ad_id` (typed PK column) |
| `field_type` | `NEW.field_type` (typed PK column) |
| `old_status` | `OLD.data->'adGroupAdAssetView'->'policySummary'->>'approvalStatus'` |
| `new_status` | `NEW.data->'adGroupAdAssetView'->'policySummary'->>'approvalStatus'` |
| `asset_content` | JOIN to `ads_v2.assets`: `COALESCE(textAsset.text, sitelinkAsset.linkText, calloutAsset.calloutText, structuredSnippetAsset.header, asset.name)` |
| `asset_type` | `NEW.data->'asset'->>'type'` |
| `campaign_name` | `NEW.data->'campaign'->>'name'` |
| `campaign_id` | `(NEW.data->'campaign'->>'id')::bigint` |
| `ad_group_name` | `NEW.data->'adGroup'->>'name'` |
| `ad_group_id` | `NEW.ad_group_id` |
| `policy_topics` | `NEW.data->'adGroupAdAssetView'->'policySummary'->'policyTopicEntries'` |

**Note on asset content JOIN:** The trigger queries `ads_v2.assets` to get content. If the assets table hasn't been synced yet this cycle, the content will be from the previous sync. This is acceptable — asset content (the text itself) rarely changes. The sync order above minimises this risk.

### Trigger 2: Extension asset (`ads_v2.assets`)

**Watches:** `data->'asset'->'policySummary'->>'approvalStatus'`

**Fires when:** The approval status value changes between OLD and NEW. Only relevant for assets that have a `policySummary` (extensions). If both OLD and NEW lack a `policySummary` (TEXT/IMAGE assets), this trigger does nothing.

**On change, logs:**

| Field | Source |
|---|---|
| `entity_type` | `'EXTENSION'` |
| `entity_key` | `'EXTENSION:' \|\| customer_id \|\| ':' \|\| asset_id \|\| '::'` |
| `asset_id` | `NEW.asset_id` (typed PK column) |
| `ad_id` | `NULL` |
| `field_type` | First entry in `data->'asset'->'fieldTypePolicySummaries'->0->>'assetFieldType'` |
| `old_status` | `OLD.data->'asset'->'policySummary'->>'approvalStatus'` |
| `new_status` | `NEW.data->'asset'->'policySummary'->>'approvalStatus'` |
| `asset_content` | Extract from `NEW.data->'asset'` based on type: `sitelinkAsset.linkText`, `calloutAsset.calloutText`, `structuredSnippetAsset.header` |
| `asset_type` | `NEW.data->'asset'->>'type'` |
| `campaign_name` | `NULL` (global verdict, no campaign context) |
| `campaign_id` | `NULL` |
| `ad_group_name` | `NULL` |
| `ad_group_id` | `NULL` |
| `policy_topics` | `NEW.data->'asset'->'policySummary'->'policyTopicEntries'` |

**No JOIN needed:** Extension asset content is in the same row.

### Trigger 3: Ad (`ads_v2.ads`)

**Watches:** `data->'adGroupAd'->'policySummary'->>'approvalStatus'`

**Fires when:** The approval status value changes between OLD and NEW.

**On change, logs:**

| Field | Source |
|---|---|
| `entity_type` | `'AD'` |
| `entity_key` | `'AD:' \|\| customer_id \|\| '::' \|\| ad_id \|\| ':'` |
| `asset_id` | `NULL` |
| `ad_id` | `NEW.ad_id` (typed PK column) |
| `field_type` | `NULL` |
| `old_status` | `OLD.data->'adGroupAd'->'policySummary'->>'approvalStatus'` |
| `new_status` | `NEW.data->'adGroupAd'->'policySummary'->>'approvalStatus'` |
| `asset_content` | `NULL` |
| `asset_type` | `NEW.data->'adGroupAd'->'ad'->>'type'` (e.g. RESPONSIVE_SEARCH_AD) |
| `campaign_name` | `NEW.data->'campaign'->>'name'` |
| `campaign_id` | `(NEW.data->'campaign'->>'id')::bigint` |
| `ad_group_name` | `NEW.data->'adGroup'->>'name'` |
| `ad_group_id` | `(NEW.data->'adGroup'->>'id')::bigint` |
| `policy_topics` | `NEW.data->'adGroupAd'->'policySummary'->'policyTopicEntries'` |

**No JOIN needed:** Ad context is in the same row.

## Bootstrap

After the first sync for a customer, run a one-time query that inserts a log entry for EVERY entity. `old_status = NULL` indicates baseline — "this is the state we found it in."

### Handling entities without a policySummary

TEXT and IMAGE assets in the `assets` table have no `policySummary`. They are NOT bootstrapped from the `assets` table — their approval status only exists at the `ad_group_ad_asset_view` level.

`ad_group_ad_asset_view` rows where `policySummary` is null (review not yet complete) ARE bootstrapped with `new_status = NULL`. This distinguishes them from entities that have a status:

- `old_status = NULL, new_status = 'APPROVED'` → baseline, entity was approved when we started watching
- `old_status = NULL, new_status = 'DISAPPROVED'` → baseline, entity was already disapproved
- `old_status = NULL, new_status = NULL` → baseline, entity has no review status yet

When a null-status entity later receives a review, the trigger fires with `OLD = NULL, NEW = 'APPROVED'` (or DISAPPROVED). This is a real state change (review completed), not a false baseline entry, because the bootstrap already recorded the null state.

### Bootstrap queries

Three queries, one per entity type:

#### Bootstrap 1: All asset-in-ad rows

```sql
INSERT INTO ads_v2.policy_timeline (
  entity_key, entity_type, customer_id, asset_id, ad_id, field_type,
  old_status, new_status, asset_content, asset_type,
  campaign_name, campaign_id, ad_group_name, ad_group_id, policy_topics
)
SELECT
  'ASSET_IN_AD:' || v.customer_id || ':' || v.asset_id || ':' || v.ad_id || ':' || v.field_type,
  'ASSET_IN_AD',
  v.customer_id,
  v.asset_id,
  v.ad_id,
  v.field_type,
  NULL,
  v.data->'adGroupAdAssetView'->'policySummary'->>'approvalStatus',
  COALESCE(
    a.data->'asset'->'textAsset'->>'text',
    a.data->'asset'->'sitelinkAsset'->>'linkText',
    a.data->'asset'->'calloutAsset'->>'calloutText',
    a.data->'asset'->'structuredSnippetAsset'->>'header',
    a.data->'asset'->>'name'
  ),
  v.data->'asset'->>'type',
  v.data->'campaign'->>'name',
  (v.data->'campaign'->>'id')::bigint,
  v.data->'adGroup'->>'name',
  v.ad_group_id,
  v.data->'adGroupAdAssetView'->'policySummary'->'policyTopicEntries'
FROM ads_v2.ad_group_ad_asset_view v
LEFT JOIN ads_v2.assets a ON a.asset_id = v.asset_id AND a.customer_id = v.customer_id;
```

Note: No WHERE filter. Every row gets a baseline entry regardless of whether it has a policySummary or not.

#### Bootstrap 2: All extension assets with policySummary

```sql
INSERT INTO ads_v2.policy_timeline (
  entity_key, entity_type, customer_id, asset_id, ad_id, field_type,
  old_status, new_status, asset_content, asset_type,
  campaign_name, campaign_id, ad_group_name, ad_group_id, policy_topics
)
SELECT
  'EXTENSION:' || a.customer_id || ':' || a.asset_id || '::',
  'EXTENSION',
  a.customer_id,
  a.asset_id,
  NULL,
  a.data->'asset'->'fieldTypePolicySummaries'->0->>'assetFieldType',
  NULL,
  a.data->'asset'->'policySummary'->>'approvalStatus',
  COALESCE(
    a.data->'asset'->'sitelinkAsset'->>'linkText',
    a.data->'asset'->'calloutAsset'->>'calloutText',
    a.data->'asset'->'structuredSnippetAsset'->>'header',
    a.data->'asset'->>'name'
  ),
  a.data->'asset'->>'type',
  NULL,
  NULL,
  NULL,
  NULL,
  a.data->'asset'->'policySummary'->'policyTopicEntries'
FROM ads_v2.assets a
WHERE a.data->'asset'->'policySummary' IS NOT NULL;
```

Note: Filtered to assets WITH policySummary. TEXT/IMAGE assets without policySummary are tracked via `ad_group_ad_asset_view` (Bootstrap 1), not here.

#### Bootstrap 3: All ads

```sql
INSERT INTO ads_v2.policy_timeline (
  entity_key, entity_type, customer_id, asset_id, ad_id, field_type,
  old_status, new_status, asset_content, asset_type,
  campaign_name, campaign_id, ad_group_name, ad_group_id, policy_topics
)
SELECT
  'AD:' || ad.customer_id || '::' || ad.ad_id || ':',
  'AD',
  ad.customer_id,
  NULL,
  ad.ad_id,
  NULL,
  NULL,
  ad.data->'adGroupAd'->'policySummary'->>'approvalStatus',
  NULL,
  ad.data->'adGroupAd'->'ad'->>'type',
  ad.data->'campaign'->>'name',
  (ad.data->'campaign'->>'id')::bigint,
  ad.data->'adGroup'->>'name',
  (ad.data->'adGroup'->>'id')::bigint,
  ad.data->'adGroupAd'->'policySummary'->'policyTopicEntries'
FROM ads_v2.ads ad;
```

Note: No WHERE filter. Every ad gets a baseline entry.

## Bootstrap Guard

Bootstrap must run exactly once per customer. Track via a `bootstrapped` boolean column on `ads_v2.sync_runs` or by checking if any log entries exist for this `customer_id`:

```sql
-- Only bootstrap if no log entries exist for this customer
IF NOT EXISTS (SELECT 1 FROM ads_v2.policy_timeline WHERE customer_id = p_customer_id) THEN
  -- run bootstrap queries
END IF;
```

## What This Does NOT Include

- Severity scoring
- Resolution tracking (open/closed incidents)
- Alert/notification logic
- Blast radius calculation
- Flap detection

These are all downstream concerns built on top of the log. The log is the foundation — append-only events. Everything else is a view or a query on the log.
