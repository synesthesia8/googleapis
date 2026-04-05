# All Approval Change Scenarios We Need To Track

> **Status:** Active — working document, needs architecture decision
> **Discovered:** 2026-04-02
> **Relevant tables:** All `ads_v2` tables

## What We Expected

One change log, one approval field, one pattern.

## What We Found

There are at least 5 distinct approval change scenarios, each with different source tables, different JSONB paths, different context requirements, and different downstream questions.

## The Scenarios

### 1. RSA Headline/Description Disapproval (per-ad context)

**Source table:** `ads_v2.ad_group_ad_asset_view`
**Approval field:** `data.adGroupAdAssetView.policySummary.approvalStatus`
**What can change:** APPROVED ↔ DISAPPROVED ↔ APPROVED_LIMITED ↔ AREA_OF_INTEREST_ONLY
**Context needed at time of change:**
- Asset ID, asset type
- Asset content (NOT in this table — lives in `ads_v2.assets`)
- Field type (HEADLINE or DESCRIPTION)
- Ad ID, ad status, ad approval status
- Ad group name
- Campaign name, campaign status
- Policy topic entries (topic + type)

**Questions this answers:**
- Which specific headline got disapproved in which ad?
- Is the ad still serving despite this headline being disapproved?
- What policy was violated?

**Complication:** Asset content (the actual text) is NOT in this row. Need to JOIN to `ads_v2.assets` to get it. Do we do the JOIN at log-write time (freeze the content) or at query time?

---

### 2. Extension Asset Disapproval (global, at asset level)

**Source table:** `ads_v2.assets`
**Approval field:** `data.asset.policySummary.approvalStatus`
**What can change:** APPROVED ↔ DISAPPROVED ↔ APPROVED_LIMITED
**Context needed at time of change:**
- Asset ID, asset type (SITELINK, CALLOUT, STRUCTURED_SNIPPET)
- Asset content (IS in this table — sitelinkAsset.linkText, calloutAsset.calloutText, etc.)
- Policy topic entries
- fieldTypePolicySummaries (approval per field type context)

**Questions this answers:**
- Which sitelink/callout got disapproved?
- What's the content?
- What policy was violated?

**Complication:** This is a GLOBAL verdict. But WHERE is this asset linked? To know the impact, you need to check `campaign_assets` and `ad_group_assets` for all places this asset is used. That's a separate query. Do we log the linked locations at change time?

---

### 3. Extension Asset Link Status Change (per-campaign or per-ad-group)

**Source table:** `ads_v2.campaign_assets` or `ads_v2.ad_group_assets`
**Status field:** `data.campaignAsset.primaryStatus` or `data.adGroupAsset.primaryStatus`
**What can change:** ELIGIBLE ↔ NOT_ELIGIBLE ↔ PAUSED ↔ REMOVED
**Context needed at time of change:**
- Asset ID, field type
- Campaign name (or ad group name)
- primaryStatusReasons (ASSET_DISAPPROVED, ASSET_LINK_REMOVED, etc.)
- primaryStatusDetails

**Questions this answers:**
- Is this sitelink actually serving in this campaign?
- WHY isn't it serving? (disapproved vs paused vs removed — different actions needed)

**Complication:** `primaryStatus` changes can be caused by the user (pausing/removing) OR by Google (disapproving). Both show up here. Do we care about user-initiated changes or only Google-initiated?

---

### 4. Ad-Level Approval Change

**Source table:** `ads_v2.ads`
**Approval field:** `data.adGroupAd.policySummary.approvalStatus`
**Also:** `data.adGroupAd.primaryStatus` and `data.adGroupAd.primaryStatusReasons`
**What can change:** APPROVED ↔ DISAPPROVED ↔ APPROVED_LIMITED ↔ UNKNOWN
**Context needed at time of change:**
- Ad ID, ad type
- Ad group name
- Campaign name, campaign status
- Policy topic entries
- primaryStatusReasons (AD_GROUP_AD_DISAPPROVED, AD_GROUP_AD_UNDER_REVIEW, etc.)
- The RSA headlines/descriptions WITH their individual policySummaryInfo (embedded in the ad data)

**Questions this answers:**
- Is this ad serving?
- What policy killed it?
- Which individual headlines/descriptions in this ad contributed to the disapproval?

**Complication:** The ad data contains the per-headline approval status EMBEDDED in the RSA structure. When the ad approval changes, was it because a specific headline got disapproved? That relationship is implicit, not explicit.

---

### 5. Campaign-Level Health Change

**Source table:** `ads_v2.campaigns`
**Status field:** `data.campaign.primaryStatus`
**Also:** `data.campaign.primaryStatusReasons`
**What can change:** ELIGIBLE ↔ LIMITED ↔ NOT_ELIGIBLE ↔ PAUSED ↔ REMOVED
**Context needed at time of change:**
- Campaign name, campaign ID
- primaryStatusReasons (HAS_ADS_DISAPPROVED, MOST_ADS_UNDER_REVIEW, etc.)
- servingStatus

**Questions this answers:**
- Is the campaign healthy?
- Is it unhealthy because of disapprovals or because of something else (budget, schedule, etc.)?

**Complication:** Campaign status changes for many reasons — not just disapprovals. Budget runs out, schedule ends, user pauses. Do we log all changes or filter to disapproval-related ones only?

---

## Open Questions

1. **Do we log at the source or at a unified layer?** One trigger per source table (5 triggers, each knowing its own JSONB path) vs one unified change detection mechanism.

2. **How much context do we freeze at log time?** Just the status change + IDs (tiny, needs JOINs to be useful) vs full context snapshot (self-contained, duplicates data).

3. **Do we care about user-initiated changes?** User pauses a campaign — is that a change we want in the log? Or only Google-initiated policy changes?

4. **How do we handle the RSA headline content problem?** The asset text isn't in the `ad_group_ad_asset_view` row. Do we JOIN and freeze it at log time, or force a JOIN at query time?

5. **Do we track ad group level changes?** Ad groups have `primaryStatus` and `primaryStatusReasons` but they're less actionable — you fix things at the ad or asset level, not the ad group level.

## Why It Matters

The architecture of the change log determines what questions we can answer later. If we freeze too little context, every query is a multi-table JOIN against historical data that may have changed. If we freeze too much, the log is bloated and rigid.

This needs an architecture decision before we build.

## Related Findings

- [Asset approval originates differently by type](google-ads-asset-approval-originates-differently-by-type.md)
