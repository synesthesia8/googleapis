# ADR-0001: Approval Log Design

## Status

Accepted

## Context

We have 9 raw JSONB tables in `ads_v2` that store everything Google Ads returns, refreshed hourly. We need to track approval status changes over time to build a timeline of every policy decision Google makes on our assets and ads.

Three distinct entity types carry approval verdicts:

1. **Asset-in-ad** — a headline or description reviewed in the context of a specific ad. Same text can have different verdicts in different ads. Source: `ad_group_ad_asset_view`. Path: `data.adGroupAdAssetView.policySummary.approvalStatus`.

2. **Extension asset** — a sitelink, callout, or structured snippet reviewed globally. One verdict everywhere. Source: `assets`. Path: `data.asset.policySummary.approvalStatus`.

3. **Ad** — an ad disapproved for reasons unrelated to individual assets (landing page issues, destination not working, combination policies). Source: `ads`. Path: `data.adGroupAd.policySummary.approvalStatus`.

See: `docs/sources/google-ads-asset-approval-originates-differently-by-type.md`
See: `docs/sources/google-ads-approval-change-scenarios.md`

## Decision

### One log table for all three entity types

One append-only table: `ads_v2.policy_timeline`. Each row is a point-in-time event recording a status transition. Rows are never updated or deleted.

### Entity identification

Each entity gets a composite key string (`entity_key`) that uniquely identifies it across all three types:

```
ASSET_IN_AD:{customer_id}:{asset_id}:{ad_id}:{field_type}
EXTENSION:{customer_id}:{asset_id}::
AD:{customer_id}::{ad_id}:
```

This enables querying the full history of any entity with one WHERE clause.

### Frozen context

Each log entry freezes the context at the time of the change: asset content, campaign name, ad group name, policy topics. This ensures log entries remain readable even if the account structure changes later (campaigns renamed, assets removed, etc.).

### Three triggers

One AFTER UPDATE trigger per source table. Each trigger:
1. Extracts the approval status from its specific JSONB path
2. Compares OLD vs NEW
3. If different, INSERTs a row into `policy_timeline` with frozen context

### Bootstrap on first sync

After the first sync, a one-time query inserts a log entry for EVERY entity regardless of status, with `old_status = NULL`. This establishes the baseline. Every subsequent change is a clean old → new transition.

### Asset content for asset-in-ad entries

The `ad_group_ad_asset_view` row does not contain asset content (the actual text). The trigger JOINs to `ads_v2.assets` at write time to freeze the content in the log entry. If the asset doesn't exist in the assets table (unlikely), `asset_content` is NULL.

## Consequences

### What becomes easier

- Full lifecycle timeline for any entity: query by `entity_key`, order by `changed_at`
- Disapproval velocity metrics: count entries by time period
- Flapping detection: count transitions for an entity in a time window
- Root cause analysis: policy topics frozen at each transition point
- Historical accuracy: context frozen at time of change, unaffected by later account changes

### What becomes harder

- Log table grows indefinitely (but at our scale — maybe 100 entries per sync — this is years before it matters)
- Three triggers add write overhead on every sync (but `IS DISTINCT FROM` on a specific JSONB path is cheap)
- Asset content JOIN in the trigger adds one lookup per changed asset-in-ad row (but only rows that actually changed, not all rows)

### What we need to watch for

- Bootstrap must run exactly once per customer. Running it twice duplicates the baseline.
- If a new source table needs tracking in the future (e.g. `customer_assets`), add a new trigger. The log table doesn't change.
- The `entity_key` format is a contract. Changing it breaks historical queries.
