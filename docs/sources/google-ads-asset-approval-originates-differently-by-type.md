# Approval Originates From Three Different Places

> **Status:** Active
> **Discovered:** 2026-04-02
> **Relevant tables:** `ads_v2.assets`, `ads_v2.ad_group_ad_asset_view`, `ads_v2.ads`, `ads_v2.campaign_assets`, `ads_v2.ad_group_assets`

## What We Expected

Every asset has an approval status. Query one place, get the verdict. An asset is either approved or disapproved.

## What We Found

There are two completely separate approval systems. Google decides where to review an asset based on its type:

**1. Extension assets** (SITELINK, CALLOUT, STRUCTURED_SNIPPET) are reviewed independently. Google looks at the asset content on its own and issues a standalone verdict. This verdict lives on the asset itself in `asset.policySummary` and cascades into the link tables (`campaign_assets.primaryStatus`, `ad_group_assets.primaryStatus`).

**2. RSA content assets** (TEXT headlines/descriptions, IMAGE) are NOT reviewed independently. Google only reviews them in the context of the specific ad they appear in. The same headline — identical text — can be APPROVED in one ad and DISAPPROVED in another. There is no standalone verdict. The approval lives in `ad_group_ad_asset_view.adGroupAdAssetView.policySummary`, not on the asset itself.

**3. The ad itself** can be disapproved for reasons unrelated to any individual asset. Landing page issues (`DESTINATION_NOT_WORKING`, `DESTINATION_NOT_ACCESSIBLE`), combination policies, or the overall ad context. No specific asset is flagged — the ad as a whole is disapproved. The approval lives in `ads.data.adGroupAd.policySummary`.

| Entity | Reviewed how | Approval lives where | Can differ per ad? |
|---|---|---|---|
| SITELINK | Standalone | `assets.data.asset.policySummary` | No — same verdict everywhere |
| CALLOUT | Standalone | `assets.data.asset.policySummary` | No |
| STRUCTURED_SNIPPET | Standalone | `assets.data.asset.policySummary` | No |
| TEXT (headline/description) | Per-ad context | `ad_group_ad_asset_view.data.adGroupAdAssetView.policySummary` | Yes |
| IMAGE | Per-ad context | `ad_group_ad_asset_view.data.adGroupAdAssetView.policySummary` | Yes |
| The ad itself | Per-ad | `ads.data.adGroupAd.policySummary` | N/A — it IS the ad |

## Evidence

**Extension asset (standalone review):**

Asset 175667682299 — SITELINK "Terms & Conditions":
```json
// assets table — HAS a standalone verdict
"asset": {
  "policySummary": {
    "reviewStatus": "REVIEWED",
    "approvalStatus": "DISAPPROVED",
    "policyTopicEntries": [{"type": "FULLY_LIMITED", "topic": "GOVERNMENT_DOCUMENTS_AND_OFFICIAL_SERVICES"}]
  },
  "fieldTypePolicySummaries": [
    {"assetFieldType": "SITELINK", "policySummaryInfo": {"approvalStatus": "DISAPPROVED"}}
  ]
}
```

**RSA content asset (per-ad-context review):**

Asset 175753829113 — TEXT "Travel to Vietnam":
```json
// assets table — NO policySummary, NO fieldTypePolicySummaries
"asset": {
  "id": "175753829113",
  "type": "TEXT",
  "textAsset": {"text": "Travel to Vietnam"}
  // policySummary does not exist
}

// ad_group_ad_asset_view — APPROVED in this ad
"adGroupAdAssetView": {
  "policySummary": {"reviewStatus": "REVIEWED", "approvalStatus": "APPROVED"}
}

// ad_group_ad_asset_view — DISAPPROVED in a different ad (same text)
"adGroupAdAssetView": {
  "policySummary": {
    "reviewStatus": "REVIEWED",
    "approvalStatus": "DISAPPROVED",
    "policyTopicEntries": [{"type": "FULLY_LIMITED", "topic": "GOVERNMENT_DOCUMENTS_AND_OFFICIAL_SERVICES"}]
  }
}
```

**Quantified across the account:**
```
Assets WITH policySummary (65):
  SITELINK: 53
  CALLOUT: 9
  STRUCTURED_SNIPPET: 3

Assets WITHOUT policySummary (541):
  TEXT: 515
  IMAGE: 26
```

100% correlation. No exceptions in our data.

## Why It Matters

1. There is no single query that returns "all disapproved assets." You must query both the `assets` table (for extensions) and `ad_group_ad_asset_view` (for RSA content) and UNION the results.

2. A disapproved RSA headline is NOT a property of the asset — it's a property of the asset-in-ad combination. The same headline text can be approved in one ad and disapproved in another (likely due to different landing pages, different description pairings, or different ad-level context).

3. Change detection for RSA content disapprovals must monitor the `ad_group_ad_asset_view` table, not the `assets` table. The asset itself will never change status because it has no status.

4. The cascade works differently:
   - Extension disapproval: asset → campaign_asset/ad_group_asset `primaryStatus = NOT_ELIGIBLE` → campaign `primaryStatusReasons` may include `HAS_ADS_DISAPPROVED`
   - RSA content disapproval: ad_group_ad_asset_view → ad `policySummary.approvalStatus = DISAPPROVED` → campaign `primaryStatusReasons` includes `HAS_ADS_DISAPPROVED`

## Related Findings

- [TEMPLATE.md](TEMPLATE.md) — template for new findings
