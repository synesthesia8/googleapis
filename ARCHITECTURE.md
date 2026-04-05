# Architecture

## Data Flow

```
Google Ads Account
  ↓ GAQL queries (9 resource types, every available field)
Google Ads Script (runs hourly inside Google Ads)
  ↓ HTTP POST (batches of 200 rows, API key auth)
Supabase Edge Function
  ↓ Routes to RPC by resource type
Postgres (ads_v2 schema)
  ↓ UPSERT into raw tables (JSONB + typed PKs)
  ↓ Triggers compare old vs new approvalStatus
Entity Ledger (append-only)
```

## Components

**Google Ads Script** — Runs inside Google Ads on Google's servers. Pulls data via GAQL, sends raw JSON objects to the Edge Function. No transformation. Tracks pull results and errors.

**Edge Function** — Receives HTTP POST, validates API key, routes to the correct Postgres RPC function based on `resource_type`. Thin pass-through. All logic lives in Postgres.

**Postgres RPC Functions** — One per resource type. Extracts PK from the JSONB, stores the entire row in a `data` column, UPSERTs on the natural key.

**Triggers** — Fire on UPSERT when `approvalStatus` changes. Append a row to the entity ledger with frozen context.

**Entity Ledger** — Append-only log of every approval status transition. Each row captures: what changed, from what to what, the full data blob at the moment of change.

**Pull Report** — One row per script run. Records status (running/completed/failed), results per resource type, errors per failed batch.

## Raw Tables

All in `ads_v2` schema. Same shape: typed PK columns + `data` jsonb + sync metadata.

| Table | PK | What it stores |
|---|---|---|
| `accounts` | `customer_id` | Google Ads account metadata |
| `campaigns` | `campaign_id, customer_id` | Campaign config, status, primary_status |
| `ad_groups` | `ad_group_id, customer_id` | Ad group config, status, bidding |
| `ads` | `ad_id, customer_id` | Ad with full RSA headlines/descriptions, policy summary |
| `assets` | `asset_id, customer_id` | Asset content (text, images, sitelinks), global policy summary |
| `customer_assets` | `customer_id, asset_id, field_type` | Account-level asset links |
| `campaign_assets` | `customer_id, campaign_id, asset_id, field_type` | Campaign-level asset links with primary_status |
| `ad_group_assets` | `customer_id, ad_group_id, asset_id, field_type` | Ad group-level asset links with primary_status |
| `ad_group_ad_asset_view` | `customer_id, ad_group_id, ad_id, asset_id, field_type` | Per-asset-per-ad approval status |
| `entity_ledger` | `id` (auto-increment) | Append-only log of every approval status transition |
| `pull_report` | `id` (uuid) | One row per script run — status, results, errors |

## Triggers

Three triggers, each watching one JSONB path for `approvalStatus` changes:

| Trigger | Table | Watches | Entity type in ledger |
|---|---|---|---|
| `trg_ledger_asset_in_ad` | `ad_group_ad_asset_view` | `adGroupAdAssetView.policySummary.approvalStatus` | ASSET_IN_AD |
| `trg_ledger_extension` | `assets` | `asset.policySummary.approvalStatus` | EXTENSION |
| `trg_ledger_ad` | `ads` | `adGroupAd.policySummary.approvalStatus` | AD |

When the watched value changes between old and new data, the trigger appends a row to `entity_ledger` with frozen context (campaign name, ad group name, asset content, policy topics, full data blob).

## Auth

Script sends `x-api-key` header → Edge Function compares against `INGEST_API_KEY` env var → RPC functions use `service_role` key internally. RLS enabled on all tables blocks direct REST API access. Edge Function has `verify_jwt = false` so no Supabase anon key is needed.
