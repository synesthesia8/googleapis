# Google Ads API — Source Findings

Data model discoveries, undocumented behavior, and API quirks found during development of the asset policy monitor.

---

## Asset Approval: Two Different Systems

**Date discovered:** 2026-04-02

**Context:** Building a disapproval monitoring system. Tried to get per-asset approval status from a single source. Discovered there are two completely different approval systems depending on asset type.

**Finding:** Google reviews extension assets (sitelinks, callouts, structured snippets) independently of ads. But it reviews RSA content assets (headlines, descriptions, images) only in the context of the specific ad they appear in.

**Evidence:**

Asset 175753829113 ("Travel to Vietnam", TEXT type):
- `assets` table: NO `policySummary`, NO `fieldTypePolicySummaries` — Google doesn't review this asset standalone
- `ad_group_ad_asset_view` in Ad 800370825012: `policySummary.approvalStatus = "DISAPPROVED"` with policy topic `GOVERNMENT_DOCUMENTS_AND_OFFICIAL_SERVICES`
- `ad_group_ad_asset_view` in Ad 797357800794: `policySummary.approvalStatus = "APPROVED"`
- Same text, different ads, different approval outcomes

Asset 175667682299 ("Terms & Conditions", SITELINK type):
- `assets` table: HAS `policySummary.approvalStatus = "DISAPPROVED"` and `fieldTypePolicySummaries[0].assetFieldType = "SITELINK"` with `approvalStatus = "DISAPPROVED"`
- Google reviews this asset independently of any ad

**Impact:**

| Asset type | Where disapproval originates | Where to query it |
|---|---|---|
| SITELINK, CALLOUT, STRUCTURED_SNIPPET | `assets.data.asset.policySummary` | `assets` table (global) + `campaign_assets` / `ad_group_assets` (link-level `primaryStatus`) |
| TEXT (headlines/descriptions), IMAGE | `ad_group_ad_asset_view.data.adGroupAdAssetView.policySummary` | `ad_group_ad_asset_view` table (per-ad context) |

Any view that shows "all disapprovals" MUST query both sources. There is no single table that contains all disapproval data.

---

## Asset Content Lives Separately From Approval

**Date discovered:** 2026-04-02

**Context:** Trying to show "what was disapproved" in a single query.

**Finding:** The `ad_group_ad_asset_view` table has per-asset-per-ad approval status but does NOT carry the asset content. It only has `asset.id`, `asset.type`, and `asset.resourceName`. To get the actual text ("Travel to Vietnam"), image URL, or sitelink text, you must JOIN to the `assets` table.

**Evidence:**

`ad_group_ad_asset_view` row for asset 175753829113:
```json
"asset": {
  "id": "175753829113",
  "type": "TEXT",
  "resourceName": "customers/6237763056/assets/175753829113"
}
```
No `textAsset`, no content.

`assets` table row for same asset:
```json
"asset": {
  "id": "175753829113",
  "type": "TEXT",
  "textAsset": {"text": "Travel to Vietnam"},
  "source": "ADVERTISER"
}
```

**Impact:** Any view showing disapproved assets with their content requires a JOIN between `ad_group_ad_asset_view` and `assets` on `asset_id + customer_id`.

---

## ad_group_ad_asset_view Only Contains HEADLINE and DESCRIPTION

**Date discovered:** 2026-04-02

**Context:** Expected to find sitelinks, callouts, images in the ad asset view.

**Finding:** `ad_group_ad_asset_view` only returns assets with `fieldType` of HEADLINE or DESCRIPTION. All other asset types (SITELINK, CALLOUT, STRUCTURED_SNIPPET, AD_IMAGE, BUSINESS_LOGO, BUSINESS_NAME) are linked at the campaign or ad group level and appear in `campaign_assets` and `ad_group_assets` instead.

**Evidence:**

```
ad_group_ad_asset_view field types:
  HEADLINE: 731
  DESCRIPTION: 269
  (nothing else)

campaign_assets field types:
  CALLOUT: 82
  SITELINK: 52
  AD_IMAGE: 36
  BUSINESS_LOGO: 17
  BUSINESS_NAME: 13
  STRUCTURED_SNIPPET: 10

ad_group_assets field types:
  SITELINK: 52
  STRUCTURED_SNIPPET: 3
```

**Impact:** To get the full picture of all assets serving with an ad, you need data from multiple tables. The ad asset view only tells you about the RSA's own headlines and descriptions.

---

## Assets Without fieldType

**Date discovered:** 2026-04-02

**Context:** Looking for `fieldType` on the asset itself.

**Finding:** The `assets` table does NOT have a `fieldType`. An asset has a `type` (TEXT, IMAGE, SITELINK, etc.) but not a field type (HEADLINE, DESCRIPTION, BUSINESS_LOGO, etc.). The field type is a property of the LINK, not the asset. A TEXT asset could be used as a HEADLINE in one ad and a DESCRIPTION in another.

**Evidence:** Asset 175753829113 (TEXT) is used as HEADLINE in 12 different ads. The `fieldType = "HEADLINE"` only appears in the `ad_group_ad_asset_view` rows, not on the asset itself.

The one exception: `asset.fieldTypePolicySummaries` contains `assetFieldType` — but this is a policy rollup, not the asset's own field type. It tells you "this asset was reviewed in the context of being used as a SITELINK."

**Impact:** To know what role an asset plays, you must look at the link table, not the asset table.

---

## TEXT Assets Have No Standalone Policy Review

**Date discovered:** 2026-04-02

**Context:** 541 out of 606 assets had no `policySummary`.

**Finding:** Google does not independently review TEXT or IMAGE assets. Only extension-type assets (SITELINK, CALLOUT, STRUCTURED_SNIPPET) get standalone reviews. TEXT assets (headlines/descriptions) are reviewed only in-context when they're part of an RSA.

**Evidence:**

```
Assets WITH policySummary (65):
  ADVERTISER SITELINK: 31
  AUTOMATICALLY_CREATED SITELINK: 22
  ADVERTISER CALLOUT: 9
  ADVERTISER STRUCTURED_SNIPPET: 2
  AUTOMATICALLY_CREATED STRUCTURED_SNIPPET: 1

Assets WITHOUT policySummary (541):
  ADVERTISER TEXT: 515
  ADVERTISER IMAGE: 26
```

100% of TEXT and IMAGE assets have no `policySummary`. 100% of SITELINK, CALLOUT, and STRUCTURED_SNIPPET assets do.

**Impact:** Don't assume a missing `policySummary` on the asset means data is missing. For TEXT/IMAGE assets, the policy data lives in `ad_group_ad_asset_view.adGroupAdAssetView.policySummary`.

---

## primaryStatus vs policySummary — Different Resources, Different Fields

**Date discovered:** 2026-04-02

**Context:** Trying to find a consistent approval field across all tables.

**Finding:** Google provides policy/approval data through different field patterns depending on the resource:

| Resource | Approval field | Status field | Reasons field |
|---|---|---|---|
| `campaign` | N/A | `primaryStatus` | `primaryStatusReasons` (e.g. `HAS_ADS_DISAPPROVED`) |
| `ad_group` | N/A | `primaryStatus` | `primaryStatusReasons` |
| `ad_group_ad` | `policySummary.approvalStatus` | `primaryStatus` | `primaryStatusReasons` (e.g. `AD_GROUP_AD_DISAPPROVED`) |
| `asset` | `policySummary.approvalStatus` (extensions only) | N/A | N/A |
| `customer_asset` | `asset.policySummary.approvalStatus` | `primaryStatus` | `primaryStatusReasons` (e.g. `ASSET_DISAPPROVED`) |
| `campaign_asset` | `asset.policySummary.approvalStatus` | `primaryStatus` | `primaryStatusReasons` |
| `ad_group_asset` | `asset.policySummary.approvalStatus` | `primaryStatus` | `primaryStatusReasons` |
| `ad_group_ad_asset_view` | `adGroupAdAssetView.policySummary.approvalStatus` | N/A | N/A |

There is no single field name that works across all resources. `primaryStatus` and `policySummary` are different concepts:
- `policySummary` = Google's policy review verdict (APPROVED, DISAPPROVED, APPROVED_LIMITED)
- `primaryStatus` = computed serving status combining policy + user actions (ELIGIBLE, NOT_ELIGIBLE, PAUSED, REMOVED)

**Impact:** Any abstraction layer must handle these different field paths per resource type.

---

## Google Ads Scripts Limitations

**Date discovered:** 2026-04-01

### No ScriptApp.getOAuthToken()

Google Ads Scripts do NOT have `ScriptApp`. That's a Google Apps Script API. There is no way to get an OAuth token from within a Google Ads Script. External API auth must use a shared secret (API key) approach.

### 50,000 Row Silent Truncation

`AdsApp.search()` caps at 50,000 rows. `hasNext()` returns `false` after 50K with no error or warning. Results are silently truncated.

### GAQL Field Availability

Not all fields in the proto/docs are available in the version of the API your account uses. `ad_group_ad.start_date_time` and `ad_group_ad.end_date_time` returned `UNRECOGNIZED_FIELD` errors despite being in the v23 proto. Always test queries against real accounts.

---

## Schema Drift Log

| Date | Resource | Change |
|---|---|---|
| 2026-04-01 | `ad_group_ad` | `start_date_time` and `end_date_time` not available via Scripts — removed from GAQL query |
| 2026-04-02 | `ad_group_ad_asset_view` | `policySummary` DOES return data (earlier testing on a REMOVED campaign row gave false impression it was always empty) |
