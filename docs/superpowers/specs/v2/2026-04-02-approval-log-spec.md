# Approval Log — Build Spec

**Decision reference:** `docs/decisions/0001-approval-log-design.md`
**Findings reference:** `docs/sources/google-ads-asset-approval-originates-differently-by-type.md`

## Table

```sql
CREATE TABLE ads_v2.approval_log (
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
CREATE INDEX idx_log_entity ON ads_v2.approval_log (entity_key, changed_at);
CREATE INDEX idx_log_time ON ads_v2.approval_log (changed_at DESC);
CREATE INDEX idx_log_disapprovals ON ads_v2.approval_log (new_status, changed_at DESC)
  WHERE new_status = 'DISAPPROVED';
CREATE INDEX idx_log_customer ON ads_v2.approval_log (customer_id, changed_at DESC);
```

## Triggers

### Trigger 1: Asset-in-ad (`ads_v2.ad_group_ad_asset_view`)

**Watches:** `data->'adGroupAdAssetView'->'policySummary'->>'approvalStatus'`

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
| `asset_content` | JOIN to `ads_v2.assets` → extract content based on asset type |
| `asset_type` | `NEW.data->'asset'->>'type'` |
| `campaign_name` | `NEW.data->'campaign'->>'name'` |
| `campaign_id` | `(NEW.data->'campaign'->>'id')::bigint` |
| `ad_group_name` | `NEW.data->'adGroup'->>'name'` |
| `ad_group_id` | `NEW.ad_group_id` |
| `policy_topics` | `NEW.data->'adGroupAdAssetView'->'policySummary'->'policyTopicEntries'` |

### Trigger 2: Extension asset (`ads_v2.assets`)

**Watches:** `data->'asset'->'policySummary'->>'approvalStatus'`

**Only fires for assets that HAVE a policySummary** (extensions only — TEXT/IMAGE assets don't have one).

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
| `asset_content` | Extract from `data->'asset'` based on type: `sitelinkAsset.linkText`, `calloutAsset.calloutText`, `structuredSnippetAsset.header` |
| `asset_type` | `NEW.data->'asset'->>'type'` |
| `campaign_name` | `NULL` (global verdict, no campaign context) |
| `campaign_id` | `NULL` |
| `ad_group_name` | `NULL` |
| `ad_group_id` | `NULL` |
| `policy_topics` | `NEW.data->'asset'->'policySummary'->'policyTopicEntries'` |

### Trigger 3: Ad (`ads_v2.ads`)

**Watches:** `data->'adGroupAd'->'policySummary'->>'approvalStatus'`

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

## Bootstrap

After the first sync for a customer, run a one-time query that inserts a log entry for EVERY entity, regardless of current status. `old_status = NULL` indicates baseline.

Three bootstrap queries, one per entity type:

### Bootstrap 1: All asset-in-ad rows

```sql
INSERT INTO ads_v2.approval_log (
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
  -- asset content via JOIN
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
LEFT JOIN ads_v2.assets a ON a.asset_id = v.asset_id AND a.customer_id = v.customer_id
WHERE v.data->'adGroupAdAssetView'->'policySummary'->>'approvalStatus' IS NOT NULL;
```

### Bootstrap 2: All extension assets with policySummary

```sql
INSERT INTO ads_v2.approval_log (
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
WHERE a.data->'asset'->'policySummary'->>'approvalStatus' IS NOT NULL;
```

### Bootstrap 3: All ads with policySummary

```sql
INSERT INTO ads_v2.approval_log (
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
FROM ads_v2.ads ad
WHERE ad.data->'adGroupAd'->'policySummary'->>'approvalStatus' IS NOT NULL;
```

## Bootstrap Guard

Bootstrap must run exactly once per customer. Track this in `ads_v2.sync_runs` or a separate flag. If bootstrap has already run for a customer, skip it.

## What This Does NOT Include

- Severity scoring
- Resolution tracking (open/closed incidents)
- Alert/notification logic
- Blast radius calculation
- Flap detection

These are all downstream concerns built on top of the log. The log is the foundation — append-only events. Everything else is a view or a query on the log.
