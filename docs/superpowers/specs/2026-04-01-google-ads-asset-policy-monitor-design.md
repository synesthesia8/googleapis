# Google Ads Asset Policy Monitor — Design Spec

## Problem

Google Ads reviews every asset (headline, image, sitelink, etc.) and decides whether it can serve. When an asset gets disapproved, it can cascade upward — killing the ad, then the ad group, then the campaign. Google notifies you about this via generic emails, hours or days late, with no context about what's actually breaking.

We need a system that:

1. Checks the full Google Ads account hierarchy every hour
2. Detects when any approval/policy status changes
3. Shows the full cascade impact (asset → ad → ad group → campaign)
4. Alerts immediately when something breaks
5. Tracks the lifecycle of every policy incident (how long was it broken? when was it fixed?)
6. Scales across multiple CIDs under an MCC

## This Is A Monitoring System

Strip away the Google Ads specifics and this is the same problem Datadog, PagerDuty, and Nagios solve: poll a system, detect state changes, track how failures cascade through a hierarchy, open/close incidents, and alert.

```
Server goes down → services on it die → APIs fail → website is down
Asset disapproved → ad might die → ad group might die → campaign stops serving
```

The design borrows three core principles from established monitoring systems:

1. **Root cause deduplication.** One asset disapproval = one incident, even if it affects 10 ads. Don't flood alerts for the same root cause.
2. **Flap detection.** If something bounces between approved and under-review every hour, stop alerting until it stabilises. Every monitoring system since Nagios (2002) has this.
3. **Freshness tracking.** If an entity hasn't been checked recently, its state is UNKNOWN — not "whatever it was last time." Stale data looking like "everything is fine" is worse than no data.

## Architecture Overview

Four pieces:

1. **Google Ads Script (MCC)** — runs hourly inside Google Ads, reads everything, sends it to Supabase
2. **Supabase Edge Function** — receives data, verifies auth, passes to Postgres
3. **Postgres (typed tables + triggers)** — stores current state, auto-detects changes, manages incidents
4. **Supabase Realtime** — pushes instant notifications when incidents open/close

### Data Flow

```
Google Ads Script (hourly, MCC-level)
  │ For each CID (batched, max 50 per run):
  │   Run GAQL queries for every resource type
  │   Flatten rows, strip nulls
  │   POST batches to Edge Function
  │   Auth: ScriptApp.getOAuthToken() (no keys stored anywhere)
  │
  ▼
Supabase Edge Function (thin pass-through)
  │ Verify Google OAuth token once per sync session (cached)
  │ Call Postgres RPC function (upsert)
  │ Return success/failure
  │
  ▼
Postgres UPSERT + Triggers
  │ Acquire advisory lock for this CID (prevents concurrent syncs)
  │ Upsert into typed dimension/fact tables
  │ Triggers fire ONLY when status fields actually change
  │ Changes logged to ads.status_changes (with flap detection)
  │ Incidents auto-opened/closed in ads.policy_incidents
  │ On first sync: bootstrap query opens incidents for existing problems
  │ On sync complete: mark unseen entities as REMOVED
  │ Refresh materialized cascade view
  │ Release advisory lock
  │
  ▼
Supabase Realtime
  Push notifications on policy_incidents table changes
```

### Why UPSERT + Triggers (Not Snapshots + Diffing)

The earlier design took a full snapshot of the account every hour (as JSONB blobs), stored it, then ran a FULL OUTER JOIN to compare consecutive snapshots. This was fundamentally flawed:

- **Metrics poison the diff.** Impressions and clicks change every hour, so every row shows as "changed" every run. Requires separating metrics from attributes at the query level and building hash columns to pre-filter.
- **JSONB comparison is expensive.** Documents over 2KB hit Postgres TOAST decompression penalty. GIN indexes on JSONB cause 5-6x write amplification.
- **99.9% of data is identical.** Storing 20K rows per hour when only 12 changed is wasteful.
- **Cascade state goes stale.** Embedding "campaign_serving_status" at incident creation time means the incident lies the moment something else changes upstream.

The UPSERT + trigger approach mirrors how monitoring systems work:

- Only stores current state (one row per entity, updated in place)
- Postgres triggers compare old vs new typed columns at write time — no diff engine needed
- Change log only contains rows that actually changed
- Cascade is a materialized view, refreshed after each sync

## Google Ads API: Asset Hierarchy

### The Hierarchy

```
Account
  └── Campaign (status, serving_status)
        └── Ad Group (status)
              └── Ad (status, approval_status, ad_strength)
                    └── Assets via ad_group_ad_asset_view
                          (approval_status, review_status, policy_topics)
```

Assets are also linked at higher levels (not just inside ads):

```
Account ← customer_asset (sitelinks, callouts at account level)
Campaign ← campaign_asset (extensions at campaign level)
Ad Group ← ad_group_asset (extensions at ad group level)
Ad ← ad_group_ad_asset_view (headlines, descriptions, images IN the ad)
```

A disapproval at ANY level can affect serving.

### Policy Approval Statuses (severity order)

| Status | Meaning |
|--------|---------|
| `DISAPPROVED` | Will not serve. Blocked. |
| `AREA_OF_INTEREST_ONLY` | Won't serve in targeted countries |
| `APPROVED_LIMITED` | Serves with restrictions |
| `APPROVED` | Serves normally |

### Policy Review Statuses

| Status | Meaning |
|--------|---------|
| `REVIEW_IN_PROGRESS` | Currently under review |
| `REVIEWED` | Primary review done |
| `UNDER_APPEAL` | Appealed or resubmitted |
| `ELIGIBLE_MAY_SERVE` | Eligible but could face further review |

### Asset Link Primary Statuses (for non-ad-level links)

| Status | Meaning |
|--------|---------|
| `ELIGIBLE` | Can serve |
| `PAUSED` | User paused |
| `REMOVED` | User removed |
| `PENDING` | Awaiting review |
| `LIMITED` | Serving partially |
| `NOT_ELIGIBLE` | Cannot serve |

### The Cascade Logic

An asset disapproval doesn't necessarily kill the ad. It depends on whether the ad has other approved assets that can fill the role:

- **RSA headline disapproved, 5 other approved headlines exist** → Ad still serves. Asset-only problem.
- **RSA headline disapproved, it was the only headline** → Ad is dead. Ad group may be dead.
- **Account-level sitelink disapproved** → Affects every campaign that inherits it, but ads still serve (sitelinks are supplementary).
- **Campaign-level callout disapproved** → Reduced ad coverage but ads still serve.

## Database Schema

### Schema: `ads`

All tables live in a custom `ads` schema, separate from the main app's `public` schema.

### Dimension Tables

#### `ads.accounts`

| Column | Type | Notes |
|--------|------|-------|
| `customer_id` | text PK | Google Ads CID e.g. "123-456-7890" |
| `descriptive_name` | text | Account name |
| `currency_code` | text | |
| `time_zone` | text | |
| `is_mcc` | boolean | |
| `mcc_customer_id` | text | Parent MCC |
| `status` | text | |
| `created_at` | timestamptz | |
| `updated_at` | timestamptz | |

#### `ads.campaigns`

| Column | Type | Notes |
|--------|------|-------|
| `campaign_id` | bigint | PK (with customer_id) |
| `customer_id` | text | FK → accounts |
| `name` | text | |
| `status` | text | ENABLED, PAUSED, REMOVED |
| `serving_status` | text | SERVING, NONE, ENDED, PENDING, SUSPENDED |
| `channel_type` | text | SEARCH, DISPLAY, PERFORMANCE_MAX |
| `channel_sub_type` | text | |
| `bidding_strategy` | text | |
| `start_date` | date | |
| `end_date` | date | |
| `budget_amount_micros` | bigint | |
| `last_checked_at` | timestamptz | Freshness tracking |
| `created_at` | timestamptz | |
| `updated_at` | timestamptz | |

#### `ads.ad_groups`

| Column | Type | Notes |
|--------|------|-------|
| `ad_group_id` | bigint | PK (with customer_id) |
| `customer_id` | text | |
| `campaign_id` | bigint | FK → campaigns |
| `name` | text | |
| `status` | text | |
| `type` | text | |
| `cpc_bid_micros` | bigint | |
| `last_checked_at` | timestamptz | Freshness tracking |
| `created_at` | timestamptz | |
| `updated_at` | timestamptz | |

#### `ads.ads`

| Column | Type | Notes |
|--------|------|-------|
| `ad_id` | bigint | PK (with customer_id) |
| `customer_id` | text | |
| `ad_group_id` | bigint | FK → ad_groups |
| `ad_type` | text | RESPONSIVE_SEARCH_AD, etc. |
| `status` | text | ENABLED, PAUSED, REMOVED |
| `approval_status` | text | APPROVED, DISAPPROVED, etc. |
| `review_status` | text | |
| `ad_strength` | text | EXCELLENT, GOOD, AVERAGE, POOR |
| `policy_topics` | jsonb | [{topic, type, evidences}] |
| `final_urls` | text[] | |
| `last_checked_at` | timestamptz | Freshness tracking |
| `created_at` | timestamptz | |
| `updated_at` | timestamptz | |

#### `ads.assets`

Stores the asset itself — what it IS, not where it's linked.

| Column | Type | Notes |
|--------|------|-------|
| `asset_id` | bigint | PK (with customer_id) |
| `customer_id` | text | |
| `name` | text | |
| `asset_type` | text | TEXT, IMAGE, YOUTUBE_VIDEO, SITELINK, CALLOUT, etc. |
| `text_content` | text | For TEXT assets (headlines, descriptions) |
| `image_url` | text | For IMAGE assets |
| `image_width` | int | |
| `image_height` | int | |
| `youtube_video_id` | text | For VIDEO assets |
| `sitelink_text` | text | For SITELINK assets |
| `sitelink_desc1` | text | |
| `sitelink_desc2` | text | |
| `callout_text` | text | For CALLOUT assets |
| `snippet_header` | text | For STRUCTURED_SNIPPET |
| `snippet_values` | text[] | |
| `phone_number` | text | For CALL assets |
| `global_approval` | text | Asset-level approval (context-free) |
| `global_review` | text | |
| `global_policy_topics` | jsonb | |
| `last_checked_at` | timestamptz | Freshness tracking |
| `created_at` | timestamptz | |
| `updated_at` | timestamptz | |


### Fact Table: Asset Links

The core table. One row per asset-to-entity relationship, at every hierarchy level.

#### `ads.asset_links`

| Column | Type | Notes |
|--------|------|-------|
| `id` | bigint (generated) | Surrogate PK |
| `customer_id` | text | |
| `link_level` | text | CUSTOMER, CAMPAIGN, AD_GROUP, AD |
| `asset_id` | bigint | FK → assets |
| `field_type` | text | HEADLINE, DESCRIPTION, SITELINK, etc. |
| `campaign_id` | bigint | null for CUSTOMER level |
| `ad_group_id` | bigint | null for CUSTOMER/CAMPAIGN level |
| `ad_id` | bigint | only for AD level |
| `link_status` | text | ENABLED, PAUSED, REMOVED |
| `approval_status` | text | DISAPPROVED, APPROVED_LIMITED, etc. |
| `review_status` | text | |
| `primary_status` | text | ELIGIBLE, NOT_ELIGIBLE, PENDING, LIMITED |
| `primary_status_reasons` | text[] | |
| `policy_topics` | jsonb | [{topic, type, evidences}] |
| `is_enabled` | boolean | AD level only |
| `performance_label` | text | BEST, GOOD, LOW (AD level only) |
| `pinned_field` | text | AD level only |
| `asset_source` | text | |
| `last_sync_id` | uuid | Tracks which sync last touched this row |
| `last_checked_at` | timestamptz | Freshness tracking |
| `first_seen_at` | timestamptz | |
| `updated_at` | timestamptz | |

**Natural key (UNIQUE constraint):** `(customer_id, link_level, asset_id, field_type, COALESCE(campaign_id, 0), COALESCE(ad_group_id, 0), COALESCE(ad_id, 0))`

Note: `COALESCE(..., 0)` is a pragmatic choice to avoid nullable columns in the unique constraint. Google Ads entity IDs are always positive integers, so `0` is safe as a sentinel value. The surrogate `id` is the actual PK, used as FK from status_changes and policy_incidents for referential integrity.

### Change Detection Tables

#### `ads.status_changes`

Every status change, forever. The audit trail.

| Column | Type | Notes |
|--------|------|-------|
| `id` | bigint (generated) | PK |
| `customer_id` | text NOT NULL | |
| `entity_type` | text NOT NULL | ASSET_LINK, AD, AD_GROUP, CAMPAIGN |
| `entity_id` | bigint NOT NULL | Surrogate FK to the source table |
| `field_name` | text NOT NULL | Which field changed |
| `old_value` | text | |
| `new_value` | text | |
| `changed_at` | timestamptz NOT NULL | |

#### `ads.policy_alerts`

Per-entity alerts. One alert per asset_link or ad that has a non-approved status. Fires when the entity goes non-approved, resolves when it goes back to approved. No ambiguity about what to watch — it's always the same field on the same row that triggered it.

| Column | Type | Notes |
|--------|------|-------|
| `id` | bigint (generated) | PK |
| `customer_id` | text NOT NULL | |
| `incident_id` | uuid | FK → policy_incidents (parent incident) |
| `entity_type` | text NOT NULL | ASSET_LINK, AD |
| `entity_id` | bigint NOT NULL | Surrogate FK to the source table |
| `asset_id` | bigint NOT NULL | Which asset this relates to (for grouping) |
| `approval_status` | text NOT NULL | What it changed TO |
| `previous_status` | text | What it changed FROM (null on bootstrap) |
| `policy_topic_names` | text[] | Just the topic strings |
| `fired_at` | timestamptz NOT NULL | |
| `resolved_at` | timestamptz | null = still firing |
| `status` | text NOT NULL | FIRING, RESOLVED |

#### `ads.policy_incidents`

Root-cause-level incident tracking. Groups alerts by asset. One incident per `(customer_id, asset_id)`. Stays OPEN as long as any child alert is FIRING. Auto-closes when the last alert resolves. Slim columns only (no large JSONB) so Supabase Realtime doesn't truncate.

| Column | Type | Notes |
|--------|------|-------|
| `id` | uuid | PK |
| `customer_id` | text NOT NULL | |
| `asset_id` | bigint NOT NULL | The root cause: which asset |
| `alert_count` | int NOT NULL DEFAULT 0 | Total alerts (FIRING + RESOLVED) |
| `firing_count` | int NOT NULL DEFAULT 0 | Currently FIRING alerts |
| `opened_at` | timestamptz NOT NULL | |
| `resolved_at` | timestamptz | null = still open |
| `resolution_duration` | interval | Generated: resolved_at - opened_at |
| `status` | text NOT NULL | OPEN, RESOLVED |

The incident resolves when `firing_count` reaches 0. If a new alert fires after resolution, the incident reopens (`resolved_at` is cleared, `status` returns to OPEN).

### Flap Detection

#### `ads.flap_state`

Tracks entities that are bouncing between states. Suppresses alerts and reduces change log noise.

| Column | Type | Notes |
|--------|------|-------|
| `entity_type` | text NOT NULL | ASSET_LINK, AD, etc. |
| `entity_id` | bigint NOT NULL | Surrogate FK |
| `field_name` | text NOT NULL | Which field is flapping |
| `transition_count` | int NOT NULL DEFAULT 0 | Transitions in the current window |
| `window_start` | timestamptz NOT NULL | When we started counting |
| `is_flapping` | boolean NOT NULL DEFAULT false | Suppresses alerts when true |
| `PRIMARY KEY` | | (entity_type, entity_id, field_name) |

**Flap detection logic:** If the same entity transitions the same field more than 3 times in 24 hours, mark as flapping. When flapping, status changes are still logged but incidents are NOT opened and alerts are NOT fired. The flap state resets when the entity stays stable for 24 hours.

### Metrics (Separate, Never Mixed With Status)

#### `ads.metrics_daily`

| Column | Type | Notes |
|--------|------|-------|
| `customer_id` | text | |
| `entity_type` | text | CAMPAIGN, AD_GROUP, AD |
| `entity_id` | bigint | |
| `date` | date | |
| `impressions` | bigint | |
| `clicks` | bigint | |
| `cost_micros` | bigint | |
| `conversions` | numeric | |
| `conversions_value` | numeric | |
| `ctr` | numeric | |
| `avg_cpc` | numeric | |

**Primary key:** `(customer_id, entity_type, entity_id, date)`

Hourly syncs use `TODAY` for metrics. A separate daily job uses `LAST_7_DAYS` to catch Google's retroactive corrections (up to 72 hours).

### Sync Tracking

#### `ads.sync_runs`

| Column | Type | Notes |
|--------|------|-------|
| `id` | uuid | PK |
| `customer_id` | text NOT NULL | |
| `started_at` | timestamptz NOT NULL | |
| `completed_at` | timestamptz | |
| `status` | text NOT NULL | running, completed, failed |
| `is_first_sync` | boolean NOT NULL DEFAULT false | Triggers bootstrap logic |
| `rows_by_type` | jsonb | {"campaign": 42, "asset": 1300} |
| `truncation_warnings` | text[] | Resource types that hit the 50K row cap |
| `error` | text | null on success |

### Indexes

```sql
-- Disapproved assets (the main query)
CREATE INDEX idx_asset_links_disapproved
  ON ads.asset_links (customer_id, approval_status)
  WHERE approval_status != 'APPROVED';

-- Navigate the hierarchy
CREATE INDEX idx_asset_links_hierarchy
  ON ads.asset_links (customer_id, campaign_id, ad_group_id, ad_id);

-- All links for a specific asset (for root cause grouping)
CREATE INDEX idx_asset_links_asset
  ON ads.asset_links (customer_id, asset_id);

-- UPSERT conflict target
CREATE UNIQUE INDEX idx_asset_links_natural_key
  ON ads.asset_links (customer_id, link_level, asset_id, field_type,
                      COALESCE(campaign_id, 0), COALESCE(ad_group_id, 0), COALESCE(ad_id, 0));

-- Deletion detection: find rows not touched by current sync
CREATE INDEX idx_asset_links_sync
  ON ads.asset_links (customer_id, last_sync_id);

-- Non-approved ads
CREATE INDEX idx_ads_approval
  ON ads.ads (customer_id, approval_status)
  WHERE approval_status != 'APPROVED';

-- Campaign serving status
CREATE INDEX idx_campaigns_serving
  ON ads.campaigns (customer_id, serving_status);

-- Change log lookups
CREATE INDEX idx_changes_lookup
  ON ads.status_changes (customer_id, entity_type, changed_at DESC);
CREATE INDEX idx_changes_entity
  ON ads.status_changes (entity_id, changed_at DESC);

-- Open incidents
CREATE INDEX idx_incidents_open
  ON ads.policy_incidents (customer_id, status)
  WHERE status = 'OPEN';

-- Incidents by asset (for root cause dedup — find existing incident before creating new one)
CREATE UNIQUE INDEX idx_incidents_asset_open
  ON ads.policy_incidents (customer_id, asset_id)
  WHERE status = 'OPEN';

-- Alerts: find firing alerts for an incident
CREATE INDEX idx_alerts_incident
  ON ads.policy_alerts (incident_id, status)
  WHERE status = 'FIRING';

-- Alerts: find alert for a specific entity (for resolving)
CREATE INDEX idx_alerts_entity
  ON ads.policy_alerts (entity_type, entity_id, status)
  WHERE status = 'FIRING';

-- Freshness: find stale entities
CREATE INDEX idx_campaigns_freshness
  ON ads.campaigns (customer_id, last_checked_at);
CREATE INDEX idx_asset_links_freshness
  ON ads.asset_links (customer_id, last_checked_at);
```

## Trigger Logic

### Change Detection

Triggers on `asset_links`, `ads`, `ad_groups`, and `campaigns` fire on UPDATE when any status field changes. They write to `ads.status_changes` with the old and new value, and update flap state.

Tracked fields per entity:

| Entity | Fields Tracked |
|--------|---------------|
| `asset_links` | `approval_status`, `review_status`, `primary_status`, `link_status` |
| `ads` | `approval_status`, `review_status`, `status` |
| `ad_groups` | `status` |
| `campaigns` | `status`, `serving_status` |

### Flap Detection Logic

On every status change:

1. Look up `ads.flap_state` for this entity + field
2. If `window_start` is more than 24 hours ago, reset: `transition_count = 1`, `window_start = now()`, `is_flapping = false`
3. Otherwise, increment `transition_count`
4. If `transition_count > 3`, set `is_flapping = true`

When `is_flapping = true`:
- Status changes are still logged to `ads.status_changes` (audit trail is complete)
- Incidents are NOT opened
- Alerts are NOT fired

When an entity stays stable for 24 hours (no transitions), `is_flapping` resets to false and normal alerting resumes.

### Incident Management (PagerDuty Model)

Follows the same alert → incident pattern as PagerDuty/Datadog:

**When an entity goes non-approved** (and is not flapping):
1. Create a FIRING alert on `ads.policy_alerts` for this specific entity
2. Look for an OPEN incident for this `(customer_id, asset_id)`
3. If one exists: attach the alert to it, increment `firing_count`
4. If none exists: create a new incident, attach the alert, set `firing_count = 1`

**When an entity returns to approved:**
1. Resolve the alert (`status = RESOLVED`, `resolved_at = now()`)
2. Decrement `firing_count` on the parent incident
3. If `firing_count = 0`: resolve the incident (`status = RESOLVED`, `resolved_at = now()`)

**When a resolved incident gets a new alert:**
1. Reopen the incident (`status = OPEN`, `resolved_at = NULL`)
2. Increment `firing_count`

This means:
- An asset disapproved globally AND in 3 ad contexts = 1 incident with 4 alerts
- When 2 of those contexts re-approve, the incident stays OPEN (2 alerts still FIRING)
- When the last alert resolves, the incident auto-closes
- No ambiguity about "which field to watch" — each alert watches its own row

### First Sync Bootstrap

On the first sync for a CID (`sync_runs.is_first_sync = true`), after all upserts complete within the same transaction:

1. Query all asset_links where `approval_status != 'APPROVED'`
2. For each non-approved asset_link, create a FIRING alert with `previous_status = NULL` (indicating baseline, not a transition)
3. Group alerts by `(customer_id, asset_id)` and create one incident per group
4. This is part of the upsert RPC transaction, not a separate step — if the sync fails partway, no orphan alerts/incidents are created

### Concurrency Control

Each sync acquires a Postgres advisory lock keyed on `customer_id` at the start of the upsert RPC:

```sql
SELECT pg_advisory_xact_lock(hashtext(p_customer_id));
```

This prevents two concurrent syncs for the same CID from interleaving their upserts. The lock is transaction-scoped — it auto-releases when the transaction commits or rolls back. No manual cleanup needed, no stuck locks if the Edge Function crashes.

### Handling Deletions

Deletion detection uses `last_sync_id` rather than timestamps (avoids clock skew issues):

1. Every upsert stamps the current `sync_id` on each row via the `last_sync_id` column
2. After all upserts complete for a CID, a cleanup query runs:
   ```sql
   UPDATE ads.asset_links
   SET link_status = 'REMOVED', updated_at = now()
   WHERE customer_id = p_customer_id
     AND last_sync_id != p_sync_id
     AND link_status != 'REMOVED';
   ```
3. This triggers the normal change detection (link_status changed), which logs the removal
4. Cleanup ONLY runs when `sync_runs.status = 'completed'` — never on failed syncs

## The Cascade View

A MATERIALIZED VIEW that joins asset_links → assets → ads → ad_groups → campaigns. Refreshed after each successful sync. This avoids the cost of a 5-table join on every query.

```sql
REFRESH MATERIALIZED VIEW CONCURRENTLY ads.cascade_status;
```

`CONCURRENTLY` means the view stays queryable during refresh — no downtime.

Derived `impact_level` column:

| Impact Level | Meaning |
|-------------|---------|
| `AD_KILLED` | Asset disapproval has caused the parent ad to be disapproved |
| `ASSET_ONLY` | Asset is disapproved but the parent ad still serves |
| `LIMITED_REACH` | Asset is approved with limitations |
| `GEO_RESTRICTED` | Asset only serves for area-of-interest queries |

### Freshness in the Cascade View

The cascade view includes a `freshness` column:

```sql
CASE
  WHEN last_checked_at > now() - interval '2 hours' THEN 'FRESH'
  WHEN last_checked_at > now() - interval '6 hours' THEN 'STALE'
  ELSE 'UNKNOWN'
END AS freshness
```

Entities with `STALE` or `UNKNOWN` freshness are flagged in the output. A query showing "everything is fine" but with UNKNOWN freshness means the pipeline is broken, not that the account is healthy.

Key queries the view supports:

```sql
-- What's broken and what's it killing?
SELECT * FROM ads.cascade_status
WHERE customer_id = '123-456-7890' AND freshness = 'FRESH';

-- How many ads are dead because of asset disapprovals?
SELECT impact_level, count(*) FROM ads.cascade_status GROUP BY 1;

-- Which campaigns have issues?
SELECT campaign_name, campaign_serving, count(*) as issues,
       count(*) FILTER (WHERE impact_level = 'AD_KILLED') as ads_killed
FROM ads.cascade_status
GROUP BY 1, 2 ORDER BY ads_killed DESC;

-- Is the pipeline healthy? Any stale accounts?
SELECT customer_id, min(last_checked_at) as oldest_check, freshness
FROM ads.cascade_status
GROUP BY customer_id, freshness
HAVING freshness != 'FRESH';
```

## Extraction Layer: Google Ads Script

### MCC-Level Script

Runs hourly via Google Ads scheduling. Iterates all child CIDs under the MCC.

### Authentication (No Keys Stored Anywhere)

The script uses `ScriptApp.getOAuthToken()` — an ephemeral Google OAuth token that already exists because the script runs inside Google Ads. The Edge Function verifies this token once per sync session and caches the result for subsequent batch requests within the same sync. This avoids hitting Google's tokeninfo endpoint on every single batch POST.

No API keys, no secrets in sheets, no credentials in code.

### GAQL Queries

Separate queries for attributes (what we upsert and detect changes on) and metrics (stored separately, never diffed):

**Attribute queries** (9 resource types — the minimum needed for full cascade tracking):
- `customer` — account-level metadata
- `campaign` — all campaigns with status, serving_status, channel_type
- `ad_group` — all ad groups with status, type
- `ad_group_ad` — all ads with status, approval_status, review_status, ad_strength, policy_topics
- `asset` — all assets with type, content fields, global policy status
- `customer_asset` — account-level asset links with primary_status, policy info
- `campaign_asset` — campaign-level asset links
- `ad_group_asset` — ad group-level asset links
- `ad_group_ad_asset_view` — asset-in-ad view with per-combination policy status

**Metric queries** (separate, no diffing):
- Campaign metrics (`TODAY` for hourly, `LAST_7_DAYS` for daily backfill)
- Ad group metrics (same)
- Ad metrics (same)

**Not pulled** (no policy/approval fields, zero value for this system):
- `campaign_budget`, `bidding_strategy`, `conversion_action`, `label` — no approval status
- `ad_group_criterion` — keyword disapprovals are a separate concern, not part of the asset→ad cascade
- `change_event` — supplementary; our triggers handle change detection
- `asset_group`, `asset_group_asset` — PMax, out of scope

### Known Limits and Mitigations

| Limit | Impact | Mitigation |
|-------|--------|------------|
| 50,000 row silent truncation on `AdsApp.search()` | Large accounts lose data with no error | Log warning if count = 50,000. Record in `sync_runs.truncation_warnings`. For `ad_group_ad_asset_view` (most likely to exceed 50K), split query by campaign ID. |
| 30-minute execution limit (60 with `executeInParallel`) | Can't process unlimited accounts | Label-based batching: max 50 accounts per run. For 200 accounts, rotate through 4 batches — each account syncs every 4 hours. |
| 50MB/day UrlFetchApp transfer (consumer accounts) | Limits payload size | Flatten rows, strip nulls (~60% size reduction). Batch 200 rows per POST. |
| 60-second timeout per UrlFetchApp call | Slow endpoints fail | Edge Function is thin (pass-through to RPC). Should respond in <5s. |
| No overlap prevention in scheduling | Concurrent runs for same CID | Postgres advisory lock per CID prevents data corruption. Script checks sync_runs for `status = 'running'` as an early exit optimisation. |

### Payload Format

The script flattens nested Google Ads objects and strips null/empty values before sending:

```json
{
  "sync_id": "uuid",
  "customer_id": "123-456-7890",
  "resource_type": "campaign",
  "batch_index": 0,
  "rows": [
    {"campaignId": 123, "name": "My Campaign", "status": "ENABLED", "servingStatus": "SERVING"},
    ...
  ]
}
```

`batch_index` enables idempotent retry detection — the RPC function can check whether this batch was already processed.

## Supabase Edge Function

### Purpose

Thin gateway. Authenticates the request, calls a Postgres RPC function, returns.

### Auth Flow

1. Extract Bearer token from Authorization header
2. Check in-memory cache for this `sync_id` — if already verified, skip to step 5
3. POST to `https://oauth2.googleapis.com/tokeninfo?access_token={token}`
4. Check that `email` is in the `ALLOWED_EMAILS` env var. Cache the result keyed on `sync_id` (TTL: 60 minutes).
5. If valid, proceed. If not, 403.

This means the Google tokeninfo endpoint is hit once per sync session, not once per batch.

### Processing

Calls the appropriate `ads.upsert_{resource_type}(rows)` Postgres function via Supabase RPC. All transformation and insertion happens server-side in Postgres, not in the Edge Function. This avoids the 2-second CPU time limit on Edge Functions.

The Edge Function connects via Supabase's connection pooler (Supavisor, port 6543, transaction mode) to avoid exhausting Postgres connection limits.

### Env Vars (set in Supabase Dashboard)

- `ALLOWED_EMAILS` — comma-separated list of Google accounts authorized to push data
- `SUPABASE_URL` — auto-provided
- `SUPABASE_SERVICE_ROLE_KEY` — auto-provided

## Upsert RPC Functions

One Postgres function per resource type. Each function:

1. Accepts a `jsonb` parameter containing the array of rows
2. Acquires an advisory lock on the customer_id (first call per sync acquires it; subsequent calls in the same transaction are no-ops)
3. Parses the JSONB into typed columns using `jsonb_to_recordset` or `jsonb_array_elements`
4. Runs `INSERT ... ON CONFLICT DO UPDATE` against the target table
5. Sets `last_sync_id` and `last_checked_at` on every touched row
6. If any row fails validation (type mismatch, missing required field), logs the error and skips that row — does NOT fail the entire batch

On the **finalize** call (after all resource types are upserted):

1. Runs deletion detection (mark unseen rows as REMOVED)
2. If `is_first_sync`, runs the bootstrap query to open incidents for existing problems
3. Refreshes the materialized cascade view
4. Marks the sync_run as completed

## Supabase Realtime

`ads.policy_incidents` and `ads.policy_alerts` are added to the Supabase Realtime publication. Subscribers receive push notifications when:

- A new incident opens (first alert fires for an asset)
- A new alert fires (additional entity affected by same root cause)
- An alert resolves (one entity re-approved)
- An incident resolves (all alerts for that asset resolved)

Both tables are intentionally slim (text fields only, no large JSONB) to stay under Supabase Realtime's 1MB payload limit.

### Polling Fallback

Realtime is not guaranteed delivery. A polling fallback queries `policy_incidents WHERE status = 'OPEN' AND opened_at > last_check` on a schedule. This catches any events missed during listener downtime or Realtime backpressure.

## Pipeline Health Monitoring

### `ads.pipeline_health` (VIEW)

Monitors the monitoring system itself. Queries against `sync_runs` and entity freshness to detect:

| Check | Condition | Severity |
|-------|-----------|----------|
| Missing sync | No completed sync for a CID in 2+ hours | CRITICAL |
| Stuck sync | sync_run with `status = 'running'` for 45+ minutes | HIGH |
| Truncation detected | `truncation_warnings` is non-empty | HIGH |
| Sync duration increasing | avg(completed_at - started_at) trending up over last 24h | MEDIUM |
| Row count anomaly | rows_by_type for a resource differs >50% from the 7-day average | MEDIUM |

Pipeline health alerts should fire independently of asset policy alerts — if the pipeline is broken, asset alerts are meaningless.

## Data Retention

| Table | Retention | Reason |
|-------|-----------|--------|
| Dimension tables (accounts, campaigns, etc.) | Current state, updated in place | Only stores what exists now |
| `ads.status_changes` | 90 days | Audit trail. Flap detection prevents unbounded growth. |
| `ads.policy_alerts` | 90 days | Per-entity alert history. Aggregate data lives in incidents. |
| `ads.policy_incidents` | Forever | Incident lifecycle history. Small. |
| `ads.flap_state` | Current state, updated in place | Resets after 24h stability |
| `ads.metrics_daily` | 90 days | Historical metrics. Prune via pg_cron. |
| `ads.sync_runs` | 30 days | Operational metadata. Prune via pg_cron. |

## Alerting

Supabase Realtime enables push-based alerting. Subscribers (frontend app, webhook listener, Slack bot) receive events when `policy_incidents` rows are inserted or updated.

For Slack/email integration: a separate Edge Function subscribes to `policy_incidents` and forwards new incidents to the desired channel.

Alerts are suppressed for flapping entities. The flap_state table is checked before opening an incident.

## Scaling Path

Google Ads Scripts have a hard 50MB/day UrlFetchApp transfer limit. With 9 resource types and ~300 bytes per flattened row:

- **1-3 accounts**: Comfortably within 50MB/day
- **10+ accounts**: Likely exceeds it
- **50+ accounts**: Definitely exceeds it

When this limit is hit, the extraction layer migrates to the **Google Ads API Python client** running outside Google's sandbox (GitHub Actions, Cloud Run, or any cron runner). The database schema, triggers, Edge Function, and all Postgres logic remain identical — only the thing that pushes data changes.

## Future Considerations

- **PMax support**: Would require `asset_group` and `asset_group_asset` tables, plus a separate cascade path (asset_group → campaign, no ads/ad_groups). Out of scope for now.
- **Keyword monitoring**: `ad_group_criterion` has its own approval_status but keyword disapprovals don't cascade into the asset→ad hierarchy. Separate feature if needed.
- **Multi-MCC**: The schema supports multiple MCC hierarchies via `mcc_customer_id` on accounts. Each CID should be owned by exactly one MCC to prevent concurrent sync conflicts.
- **Google Change Events**: The `change_event` resource could supplement our trigger-based detection or catch changes between syncs.
- **Raw response archiving**: For backfill capability, compressed raw GAQL responses could be stored in cloud storage with lifecycle rules.
