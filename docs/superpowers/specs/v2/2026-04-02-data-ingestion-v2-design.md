# Google Ads Data Ingestion v2 — Design Spec

## Problem

v1 cherry-picked fields, renamed them, and lost data. Every time we realised a field was missing, it required a migration, script change, RPC rewrite, and deployment. The schema was coupled to our assumptions about what mattered.

## Objective

Pull EVERYTHING from Google Ads. Store it raw. Lose nothing. Build views on top later.

## Approach

ELT pattern used by Airbyte, Fivetran, and every production data pipeline:

1. **Extract** — GAQL queries pull every available field per resource type
2. **Load** — Raw JSON objects stored as JSONB in Postgres, one table per resource type
3. **Transform** — Views/materialized views built on top (separate step, separate conversation)

## Architecture

```
Google Ads Script
  → pulls 9 resource types, every field available
  → sends raw row objects (no transformation)
  → POSTs to Edge Function

Edge Function (ingest-gads-v2)
  → validates API key
  → calls ads_v2.upsert_{resource_type}() RPC
  → RPC extracts ONLY the PK from the JSONB
  → stores the entire row object in a `data` column

Postgres (ads_v2 schema)
  → 9 tables, one per resource type
  → each table: typed PK columns + data (jsonb) + sync metadata
```

## Schema: `ads_v2`

Lives alongside `ads` (v1). No shared tables, no dependencies.

### `ads_v2.accounts`

| Column | Type | Source |
|---|---|---|
| `customer_id` | text PK | `data->'customer'->>'id'` |
| `data` | jsonb NOT NULL | Entire row from GAQL |
| `last_sync_id` | uuid | Set by RPC |
| `last_checked_at` | timestamptz | Set by RPC |
| `created_at` | timestamptz | Default now() |
| `updated_at` | timestamptz | Default now() |

### `ads_v2.campaigns`

| Column | Type | Source |
|---|---|---|
| `campaign_id` | bigint | `data->'campaign'->>'id'` |
| `customer_id` | text | Set by RPC param |
| `data` | jsonb NOT NULL | Entire row from GAQL |
| `last_sync_id` | uuid | |
| `last_checked_at` | timestamptz | |
| `created_at` | timestamptz | |
| `updated_at` | timestamptz | |
| **PK** | | `(campaign_id, customer_id)` |

### `ads_v2.ad_groups`

| Column | Type | Source |
|---|---|---|
| `ad_group_id` | bigint | `data->'adGroup'->>'id'` |
| `customer_id` | text | Set by RPC param |
| `data` | jsonb NOT NULL | Entire row from GAQL |
| `last_sync_id` | uuid | |
| `last_checked_at` | timestamptz | |
| `created_at` | timestamptz | |
| `updated_at` | timestamptz | |
| **PK** | | `(ad_group_id, customer_id)` |

### `ads_v2.ads`

| Column | Type | Source |
|---|---|---|
| `ad_id` | bigint | `data->'adGroupAd'->'ad'->>'id'` |
| `customer_id` | text | Set by RPC param |
| `data` | jsonb NOT NULL | Entire row from GAQL |
| `last_sync_id` | uuid | |
| `last_checked_at` | timestamptz | |
| `created_at` | timestamptz | |
| `updated_at` | timestamptz | |
| **PK** | | `(ad_id, customer_id)` |

### `ads_v2.assets`

| Column | Type | Source |
|---|---|---|
| `asset_id` | bigint | `data->'asset'->>'id'` |
| `customer_id` | text | Set by RPC param |
| `data` | jsonb NOT NULL | Entire row from GAQL |
| `last_sync_id` | uuid | |
| `last_checked_at` | timestamptz | |
| `created_at` | timestamptz | |
| `updated_at` | timestamptz | |
| **PK** | | `(asset_id, customer_id)` |

### `ads_v2.customer_assets`

| Column | Type | Source |
|---|---|---|
| `customer_id` | text | Set by RPC param |
| `asset_id` | bigint | `data->'asset'->>'id'` |
| `field_type` | text | `data->'customerAsset'->>'fieldType'` |
| `data` | jsonb NOT NULL | Entire row from GAQL |
| `last_sync_id` | uuid | |
| `last_checked_at` | timestamptz | |
| `created_at` | timestamptz | |
| `updated_at` | timestamptz | |
| **PK** | | `(customer_id, asset_id, field_type)` |

### `ads_v2.campaign_assets`

| Column | Type | Source |
|---|---|---|
| `customer_id` | text | Set by RPC param |
| `campaign_id` | bigint | `data->'campaign'->>'id'` |
| `asset_id` | bigint | `data->'asset'->>'id'` |
| `field_type` | text | `data->'campaignAsset'->>'fieldType'` |
| `data` | jsonb NOT NULL | Entire row from GAQL |
| `last_sync_id` | uuid | |
| `last_checked_at` | timestamptz | |
| `created_at` | timestamptz | |
| `updated_at` | timestamptz | |
| **PK** | | `(customer_id, campaign_id, asset_id, field_type)` |

### `ads_v2.ad_group_assets`

| Column | Type | Source |
|---|---|---|
| `customer_id` | text | Set by RPC param |
| `ad_group_id` | bigint | `data->'adGroup'->>'id'` |
| `asset_id` | bigint | `data->'asset'->>'id'` |
| `field_type` | text | `data->'adGroupAsset'->>'fieldType'` |
| `data` | jsonb NOT NULL | Entire row from GAQL |
| `last_sync_id` | uuid | |
| `last_checked_at` | timestamptz | |
| `created_at` | timestamptz | |
| `updated_at` | timestamptz | |
| **PK** | | `(customer_id, ad_group_id, asset_id, field_type)` |

### `ads_v2.ad_group_ad_asset_view`

| Column | Type | Source |
|---|---|---|
| `customer_id` | text | Set by RPC param |
| `ad_group_id` | bigint | `data->'adGroup'->>'id'` |
| `ad_id` | bigint | `data->'adGroupAd'->'ad'->>'id'` |
| `asset_id` | bigint | `data->'asset'->>'id'` |
| `field_type` | text | `data->'adGroupAdAssetView'->>'fieldType'` |
| `data` | jsonb NOT NULL | Entire row from GAQL |
| `last_sync_id` | uuid | |
| `last_checked_at` | timestamptz | |
| `created_at` | timestamptz | |
| `updated_at` | timestamptz | |
| **PK** | | `(customer_id, ad_group_id, ad_id, asset_id, field_type)` |

### `ads_v2.sync_runs`

Same as v1 — operational metadata.

| Column | Type |
|---|---|
| `id` | uuid PK |
| `customer_id` | text NOT NULL |
| `started_at` | timestamptz |
| `completed_at` | timestamptz |
| `status` | text (running/completed/failed) |
| `rows_by_type` | jsonb |
| `truncation_warnings` | text[] |
| `error` | text |

## GAQL Queries — Pull Everything

Each query pulls EVERY available field for its resource type. GAQL doesn't have `SELECT *`, so we explicitly list all fields. The complete field lists are documented in `docs/superpowers/reference/`.

### accounts

```sql
SELECT
  customer.resource_name,
  customer.id,
  customer.descriptive_name,
  customer.currency_code,
  customer.time_zone,
  customer.tracking_url_template,
  customer.final_url_suffix,
  customer.auto_tagging_enabled,
  customer.has_partners_badge,
  customer.manager,
  customer.test_account,
  customer.optimization_score,
  customer.optimization_score_weight,
  customer.status
FROM customer
```

### campaigns

```sql
SELECT
  campaign.resource_name,
  campaign.id,
  campaign.name,
  campaign.status,
  campaign.primary_status,
  campaign.primary_status_reasons,
  campaign.serving_status,
  campaign.advertising_channel_type,
  campaign.advertising_channel_sub_type,
  campaign.experiment_type,
  campaign.ad_serving_optimization_status,
  campaign.bidding_strategy_type,
  campaign.bidding_strategy_system_status,
  campaign.start_date,
  campaign.end_date,
  campaign.campaign_budget,
  campaign.campaign_group,
  campaign.labels,
  campaign.tracking_url_template,
  campaign.final_url_suffix,
  campaign.url_custom_parameters,
  campaign.optimization_score,
  campaign.keyword_match_type,
  campaign.listing_type,
  campaign.network_settings.target_google_search,
  campaign.network_settings.target_search_network,
  campaign.network_settings.target_content_network,
  campaign.network_settings.target_partner_search_network,
  campaign.network_settings.target_youtube,
  campaign.network_settings.target_google_tv_network,
  campaign.geo_target_type_setting.positive_geo_target_type,
  campaign.geo_target_type_setting.negative_geo_target_type,
  campaign.excluded_parent_asset_field_types,
  campaign.excluded_parent_asset_set_types,
  campaign.payment_mode,
  campaign.video_brand_safety_suitability,
  campaign.contains_eu_political_advertising,
  campaign.missing_eu_political_advertising_declaration,
  campaign.brand_guidelines_enabled,
  campaign.asset_automation_settings
FROM campaign
```

### ad_groups

```sql
SELECT
  ad_group.resource_name,
  ad_group.id,
  ad_group.name,
  ad_group.status,
  ad_group.type,
  ad_group.primary_status,
  ad_group.primary_status_reasons,
  ad_group.ad_rotation_mode,
  ad_group.base_ad_group,
  ad_group.tracking_url_template,
  ad_group.url_custom_parameters,
  ad_group.campaign,
  ad_group.cpc_bid_micros,
  ad_group.effective_cpc_bid_micros,
  ad_group.cpm_bid_micros,
  ad_group.target_cpa_micros,
  ad_group.cpv_bid_micros,
  ad_group.target_cpm_micros,
  ad_group.target_roas,
  ad_group.percent_cpc_bid_micros,
  ad_group.fixed_cpm_micros,
  ad_group.target_cpv_micros,
  ad_group.target_cpc_micros,
  ad_group.optimized_targeting_enabled,
  ad_group.display_custom_bid_dimension,
  ad_group.final_url_suffix,
  ad_group.effective_target_cpa_micros,
  ad_group.effective_target_cpa_source,
  ad_group.effective_target_roas,
  ad_group.effective_target_roas_source,
  ad_group.labels,
  ad_group.excluded_parent_asset_field_types,
  ad_group.excluded_parent_asset_set_types,
  campaign.id,
  campaign.name,
  campaign.status
FROM ad_group
```

### ads (ad_group_ad)

```sql
SELECT
  ad_group_ad.resource_name,
  ad_group_ad.status,
  ad_group_ad.ad.id,
  ad_group_ad.ad.type,
  ad_group_ad.ad.name,
  ad_group_ad.ad.final_urls,
  ad_group_ad.ad.final_mobile_urls,
  ad_group_ad.ad.tracking_url_template,
  ad_group_ad.ad.final_url_suffix,
  ad_group_ad.policy_summary.approval_status,
  ad_group_ad.policy_summary.review_status,
  ad_group_ad.policy_summary.policy_topic_entries,
  ad_group_ad.ad_strength,
  ad_group_ad.action_items,
  ad_group_ad.labels,
  ad_group_ad.primary_status,
  ad_group_ad.primary_status_reasons,
  ad_group_ad.ad.responsive_search_ad.headlines,
  ad_group_ad.ad.responsive_search_ad.descriptions,
  ad_group_ad.ad.responsive_search_ad.path1,
  ad_group_ad.ad.responsive_search_ad.path2,
  ad_group.id,
  ad_group.name,
  campaign.id,
  campaign.name,
  campaign.status
FROM ad_group_ad
```

### assets

```sql
SELECT
  asset.resource_name,
  asset.id,
  asset.name,
  asset.type,
  asset.source,
  asset.final_urls,
  asset.final_mobile_urls,
  asset.tracking_url_template,
  asset.url_custom_parameters,
  asset.final_url_suffix,
  asset.policy_summary.approval_status,
  asset.policy_summary.review_status,
  asset.policy_summary.policy_topic_entries,
  asset.field_type_policy_summaries,
  asset.text_asset.text,
  asset.image_asset.full_size.url,
  asset.image_asset.full_size.width_pixels,
  asset.image_asset.full_size.height_pixels,
  asset.image_asset.mime_type,
  asset.youtube_video_asset.youtube_video_id,
  asset.youtube_video_asset.youtube_video_title,
  asset.sitelink_asset.description1,
  asset.sitelink_asset.description2,
  asset.sitelink_asset.link_text,
  asset.callout_asset.callout_text,
  asset.structured_snippet_asset.header,
  asset.structured_snippet_asset.values,
  asset.call_asset.phone_number,
  asset.call_asset.country_code,
  asset.promotion_asset.promotion_target,
  asset.price_asset.type,
  asset.lead_form_asset.business_name,
  asset.call_to_action_asset.call_to_action,
  asset.mobile_app_asset.app_id,
  asset.mobile_app_asset.app_store,
  asset.hotel_callout_asset.text,
  asset.page_feed_asset.page_url,
  asset.page_feed_asset.labels
FROM asset
```

### customer_asset

```sql
SELECT
  customer_asset.resource_name,
  customer_asset.asset,
  customer_asset.field_type,
  customer_asset.source,
  customer_asset.status,
  customer_asset.primary_status,
  customer_asset.primary_status_details,
  customer_asset.primary_status_reasons,
  asset.id,
  asset.name,
  asset.type,
  asset.policy_summary.approval_status,
  asset.policy_summary.review_status,
  asset.policy_summary.policy_topic_entries
FROM customer_asset
```

### campaign_asset

```sql
SELECT
  campaign_asset.resource_name,
  campaign_asset.campaign,
  campaign_asset.asset,
  campaign_asset.field_type,
  campaign_asset.source,
  campaign_asset.status,
  campaign_asset.primary_status,
  campaign_asset.primary_status_details,
  campaign_asset.primary_status_reasons,
  campaign.id,
  campaign.name,
  campaign.status,
  asset.id,
  asset.name,
  asset.type,
  asset.policy_summary.approval_status,
  asset.policy_summary.review_status,
  asset.policy_summary.policy_topic_entries
FROM campaign_asset
```

### ad_group_asset

```sql
SELECT
  ad_group_asset.resource_name,
  ad_group_asset.ad_group,
  ad_group_asset.asset,
  ad_group_asset.field_type,
  ad_group_asset.source,
  ad_group_asset.status,
  ad_group_asset.primary_status,
  ad_group_asset.primary_status_details,
  ad_group_asset.primary_status_reasons,
  ad_group.id,
  ad_group.name,
  ad_group.status,
  campaign.id,
  campaign.name,
  campaign.status,
  asset.id,
  asset.name,
  asset.type,
  asset.policy_summary.approval_status,
  asset.policy_summary.review_status,
  asset.policy_summary.policy_topic_entries
FROM ad_group_asset
```

### ad_group_ad_asset_view

```sql
SELECT
  ad_group_ad_asset_view.resource_name,
  ad_group_ad_asset_view.ad_group_ad,
  ad_group_ad_asset_view.asset,
  ad_group_ad_asset_view.field_type,
  ad_group_ad_asset_view.enabled,
  ad_group_ad_asset_view.policy_summary,
  ad_group_ad_asset_view.performance_label,
  ad_group_ad_asset_view.pinned_field,
  ad_group_ad_asset_view.source,
  ad_group_ad.ad.id,
  ad_group_ad.ad.type,
  ad_group_ad.status,
  ad_group_ad.policy_summary.approval_status,
  ad_group_ad.policy_summary.review_status,
  ad_group.id,
  ad_group.name,
  campaign.id,
  campaign.name,
  campaign.status,
  asset.id,
  asset.name,
  asset.type,
  asset.policy_summary.approval_status,
  asset.policy_summary.review_status
FROM ad_group_ad_asset_view
```

## Script Design

### No transformers

The script sends the raw row object from `AdsApp.search()` directly. No field mapping, no renaming, no data loss.

```javascript
function main() {
  var syncId = generateUuid_();
  var customerId = AdsApp.currentAccount().getCustomerId();

  for (var resourceType in QUERIES) {
    var rows = pullResource_(QUERIES[resourceType]);
    if (rows.length > 0) {
      pushToSupabase_(syncId, customerId, resourceType, rows);
    }
  }

  createSyncRun_(syncId, customerId);
  finalize_(syncId, customerId);
}
```

### Auth

Same as v1: `x-api-key` header with shared secret stored in Supabase Edge Function secrets.

### Batching

Same as v1: 200 rows per POST.

## RPC Functions

One per resource type. Each one:

1. Accepts `(p_customer_id text, p_sync_id text, p_rows jsonb)`
2. Extracts ONLY the PK columns from the JSONB
3. Stores the entire row in `data`
4. UPSERTs on the natural key
5. Stamps `last_sync_id` and `last_checked_at`

Example for campaigns:

```sql
CREATE FUNCTION ads_v2.upsert_campaigns(p_customer_id text, p_sync_id text, p_rows jsonb)
RETURNS void AS $$
BEGIN
  INSERT INTO ads_v2.campaigns (campaign_id, customer_id, data, last_sync_id, last_checked_at)
  SELECT
    (r->'campaign'->>'id')::bigint,
    p_customer_id,
    r,
    p_sync_id::uuid,
    now()
  FROM jsonb_array_elements(p_rows) AS r
  ON CONFLICT (campaign_id, customer_id)
  DO UPDATE SET
    data = EXCLUDED.data,
    last_sync_id = EXCLUDED.last_sync_id,
    last_checked_at = now(),
    updated_at = now();
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
```

Every RPC function follows this exact pattern. The only thing that changes is the table name and the PK extraction path.

## Edge Function

New function at `supabase/functions/ingest-gads-v2/index.ts`. Same pattern as v1 but routes to `ads_v2` schema:

- Validates `x-api-key`
- Routes `resource_type` to `ads_v2.upsert_{resource_type}()`
- Handles `create_sync_run` and `finalize`

## What v2 Does NOT Include

- Cascade view
- Change detection triggers
- Status changes table
- Alert/incident system
- Flap detection
- Pipeline health monitoring

These are all downstream concerns. They get built as views and triggers ON TOP of the raw data tables once we verify the data is landing correctly. Separate spec, separate build.

## Coexistence with v1

| Aspect | v1 | v2 |
|---|---|---|
| Schema | `ads` | `ads_v2` |
| Edge Function | `ingest-gads` | `ingest-gads-v2` |
| Script | `scripts/ad-asset-policy-monitor/main.js` | `scripts/ad-asset-policy-monitor-v2/main.js` |
| Tables | 8 typed tables | 9 JSONB tables |
| Transformers | 9 manual mapping functions | None (raw passthrough) |
| Fields pulled | ~11-20 per resource | Everything available |

Both can run simultaneously against the same Google Ads account. v1 writes to `ads.*`, v2 writes to `ads_v2.*`. Compare data in Supabase Studio.

When v2 is verified, v1 gets deleted.
