# Phase 4: Google Ads Script (Extraction Layer)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the MCC-level Google Ads Script that pulls all 9 resource types from Google Ads, flattens them, and POSTs to the Supabase Edge Function. Run it manually against a real account and verify end-to-end data flow.

**Architecture:** Single Google Ads Script running at the MCC level. Uses `AdsManagerApp.accounts()` to iterate CIDs. Each CID gets 9 attribute queries + 3 metric queries. Results are flattened, batched into 200 rows per POST, and sent to the Edge Function with `ScriptApp.getOAuthToken()` for auth.

**Tech Stack:** Google Ads Scripts (JavaScript), GAQL, UrlFetchApp

**Depends on:** Phase 3 (Edge Function + RPC functions deployed to Supabase)

**Spec reference:** `docs/superpowers/specs/2026-04-01-google-ads-asset-policy-monitor-design.md` — Extraction Layer section

---

### Task 1: Create the script skeleton with config and helpers

**Files:**
- Create: `scripts/ad-asset-policy-monitor/main.js`

- [ ] **Step 1: Write the script with config, helpers, and GAQL queries**

```javascript
// scripts/ad-asset-policy-monitor/main.js

// ─── CONFIG ─────────────────────────────────────────────────────
var EDGE_FUNCTION_URL = 'https://YOUR_PROJECT.supabase.co/functions/v1/ingest-gads';
var BATCH_SIZE = 200;

// ─── GAQL QUERIES (Attributes only — no metrics) ───────────────

var QUERIES = {
  accounts: [
    'SELECT',
    '  customer.id,',
    '  customer.descriptive_name,',
    '  customer.currency_code,',
    '  customer.time_zone,',
    '  customer.status',
    'FROM customer'
  ].join('\n'),

  campaigns: [
    'SELECT',
    '  campaign.id,',
    '  campaign.name,',
    '  campaign.status,',
    '  campaign.serving_status,',
    '  campaign.advertising_channel_type,',
    '  campaign.advertising_channel_sub_type,',
    '  campaign.bidding_strategy_type,',
    '  campaign.start_date,',
    '  campaign.end_date,',
    '  campaign.campaign_budget',
    'FROM campaign',
    'WHERE campaign.status != \'REMOVED\''
  ].join('\n'),

  ad_groups: [
    'SELECT',
    '  ad_group.id,',
    '  ad_group.name,',
    '  ad_group.status,',
    '  ad_group.type,',
    '  ad_group.cpc_bid_micros,',
    '  campaign.id,',
    '  campaign.name',
    'FROM ad_group',
    'WHERE ad_group.status != \'REMOVED\'',
    '  AND campaign.status != \'REMOVED\''
  ].join('\n'),

  ads: [
    'SELECT',
    '  ad_group_ad.ad.id,',
    '  ad_group_ad.ad.type,',
    '  ad_group_ad.status,',
    '  ad_group_ad.ad.final_urls,',
    '  ad_group_ad.policy_summary.approval_status,',
    '  ad_group_ad.policy_summary.review_status,',
    '  ad_group_ad.policy_summary.policy_topic_entries,',
    '  ad_group_ad.ad_strength,',
    '  ad_group.id,',
    '  ad_group.name,',
    '  campaign.id,',
    '  campaign.name',
    'FROM ad_group_ad',
    'WHERE ad_group_ad.status != \'REMOVED\'',
    '  AND campaign.status != \'REMOVED\''
  ].join('\n'),

  assets: [
    'SELECT',
    '  asset.id,',
    '  asset.name,',
    '  asset.type,',
    '  asset.policy_summary.approval_status,',
    '  asset.policy_summary.review_status,',
    '  asset.policy_summary.policy_topic_entries,',
    '  asset.text_asset.text,',
    '  asset.image_asset.full_size.url,',
    '  asset.image_asset.full_size.width_pixels,',
    '  asset.image_asset.full_size.height_pixels,',
    '  asset.youtube_video_asset.youtube_video_id,',
    '  asset.sitelink_asset.link_text,',
    '  asset.sitelink_asset.description1,',
    '  asset.sitelink_asset.description2,',
    '  asset.callout_asset.callout_text,',
    '  asset.structured_snippet_asset.header,',
    '  asset.structured_snippet_asset.values,',
    '  asset.call_asset.phone_number,',
    '  asset.call_asset.country_code',
    'FROM asset'
  ].join('\n'),

  customer_asset: [
    'SELECT',
    '  customer_asset.resource_name,',
    '  customer_asset.field_type,',
    '  customer_asset.status,',
    '  customer_asset.primary_status,',
    '  customer_asset.primary_status_reasons,',
    '  asset.id,',
    '  asset.name,',
    '  asset.type,',
    '  asset.policy_summary.approval_status,',
    '  asset.policy_summary.review_status,',
    '  asset.policy_summary.policy_topic_entries',
    'FROM customer_asset',
    'WHERE customer_asset.status != \'REMOVED\''
  ].join('\n'),

  campaign_asset: [
    'SELECT',
    '  campaign_asset.resource_name,',
    '  campaign_asset.field_type,',
    '  campaign_asset.status,',
    '  campaign_asset.primary_status,',
    '  campaign_asset.primary_status_reasons,',
    '  campaign.id,',
    '  campaign.name,',
    '  asset.id,',
    '  asset.name,',
    '  asset.type,',
    '  asset.policy_summary.approval_status,',
    '  asset.policy_summary.review_status,',
    '  asset.policy_summary.policy_topic_entries',
    'FROM campaign_asset',
    'WHERE campaign_asset.status != \'REMOVED\'',
    '  AND campaign.status != \'REMOVED\''
  ].join('\n'),

  ad_group_asset: [
    'SELECT',
    '  ad_group_asset.resource_name,',
    '  ad_group_asset.field_type,',
    '  ad_group_asset.status,',
    '  ad_group_asset.primary_status,',
    '  ad_group_asset.primary_status_reasons,',
    '  ad_group.id,',
    '  ad_group.name,',
    '  campaign.id,',
    '  campaign.name,',
    '  asset.id,',
    '  asset.name,',
    '  asset.type,',
    '  asset.policy_summary.approval_status,',
    '  asset.policy_summary.review_status,',
    '  asset.policy_summary.policy_topic_entries',
    'FROM ad_group_asset',
    'WHERE ad_group_asset.status != \'REMOVED\'',
    '  AND campaign.status != \'REMOVED\''
  ].join('\n'),

  ad_group_ad_asset_view: [
    'SELECT',
    '  ad_group_ad_asset_view.resource_name,',
    '  ad_group_ad_asset_view.field_type,',
    '  ad_group_ad_asset_view.enabled,',
    '  ad_group_ad_asset_view.performance_label,',
    '  ad_group_ad_asset_view.pinned_field,',
    '  ad_group_ad_asset_view.source,',
    '  ad_group_ad_asset_view.policy_summary,',
    '  ad_group_ad.ad.id,',
    '  ad_group_ad.ad.type,',
    '  ad_group_ad.status,',
    '  ad_group_ad.policy_summary.approval_status,',
    '  ad_group.id,',
    '  ad_group.name,',
    '  campaign.id,',
    '  campaign.name,',
    '  asset.id,',
    '  asset.name,',
    '  asset.type,',
    '  asset.policy_summary.approval_status,',
    '  asset.policy_summary.review_status',
    'FROM ad_group_ad_asset_view',
    'WHERE ad_group_ad.status != \'REMOVED\'',
    '  AND campaign.status != \'REMOVED\''
  ].join('\n')
};

// ─── HELPERS ────────────────────────────────────────────────────

function generateUuid_() {
  return Utilities.getUuid();
}

function getAuthToken_() {
  return ScriptApp.getOAuthToken();
}

function pullResource_(query) {
  var results = [];
  try {
    var search = AdsApp.search(query);
    while (search.hasNext()) {
      results.push(search.next());
    }
  } catch (e) {
    Logger.log('QUERY FAILED: ' + e.message);
  }
  if (results.length === 50000) {
    Logger.log('WARNING: Hit 50K row cap — results may be truncated');
  }
  return results;
}

function flattenObject_(obj, prefix, result) {
  for (var key in obj) {
    if (obj[key] === null || obj[key] === undefined || obj[key] === '') continue;
    var fullKey = prefix ? prefix + '.' + key : key;
    if (typeof obj[key] === 'object' && !Array.isArray(obj[key])) {
      flattenObject_(obj[key], fullKey, result);
    } else {
      result[fullKey] = obj[key];
    }
  }
}

function pushToSupabase_(syncId, customerId, resourceType, rows) {
  var token = getAuthToken_();
  for (var i = 0; i < rows.length; i += BATCH_SIZE) {
    var batch = rows.slice(i, i + BATCH_SIZE);
    var response = UrlFetchApp.fetch(EDGE_FUNCTION_URL, {
      method: 'post',
      contentType: 'application/json',
      headers: { 'Authorization': 'Bearer ' + token },
      muteHttpExceptions: true,
      payload: JSON.stringify({
        sync_id: syncId,
        customer_id: customerId,
        resource_type: resourceType,
        batch_index: Math.floor(i / BATCH_SIZE),
        rows: batch
      })
    });
    if (response.getResponseCode() !== 200) {
      Logger.log('PUSH FAILED [' + resourceType + ' batch ' + Math.floor(i / BATCH_SIZE) + ']: ' + response.getContentText());
    }
  }
}

function finalize_(syncId, customerId) {
  var token = getAuthToken_();
  var response = UrlFetchApp.fetch(EDGE_FUNCTION_URL, {
    method: 'post',
    contentType: 'application/json',
    headers: { 'Authorization': 'Bearer ' + token },
    muteHttpExceptions: true,
    payload: JSON.stringify({
      sync_id: syncId,
      customer_id: customerId,
      resource_type: 'finalize',
      rows: []
    })
  });
  if (response.getResponseCode() !== 200) {
    Logger.log('FINALIZE FAILED: ' + response.getContentText());
  }
}
```

- [ ] **Step 2: Commit**

```bash
git add scripts/ad-asset-policy-monitor/
git commit -m "feat: create Google Ads Script skeleton with GAQL queries and helpers"
```

---

### Task 2: Add row transformer functions

**Files:**
- Modify: `scripts/ad-asset-policy-monitor/main.js`

Each resource type needs a transformer that maps the Google Ads camelCase JS object to the flat JSON our RPC functions expect. This is the mapping layer between Google's schema and ours.

- [ ] **Step 1: Add transformer functions to the script**

Append to `main.js`:

```javascript
// ─── ROW TRANSFORMERS ───────────────────────────────────────────
// Map Google Ads JS objects → flat JSON matching our RPC function param names

var TRANSFORMERS = {
  accounts: function(row) {
    var c = row.customer;
    return {
      descriptiveName: c.descriptiveName || '',
      currencyCode: c.currencyCode || '',
      timeZone: c.timeZone || '',
      status: c.status || ''
    };
  },

  campaigns: function(row) {
    var c = row.campaign;
    return {
      campaignId: c.id,
      name: c.name,
      status: c.status,
      servingStatus: c.servingStatus || '',
      channelType: c.advertisingChannelType || '',
      channelSubType: c.advertisingChannelSubType || '',
      biddingStrategy: c.biddingStrategyType || '',
      startDate: c.startDate || null,
      endDate: c.endDate || null,
      budgetAmountMicros: row.campaignBudget ? row.campaignBudget.amountMicros : null
    };
  },

  ad_groups: function(row) {
    return {
      adGroupId: row.adGroup.id,
      campaignId: row.campaign.id,
      name: row.adGroup.name,
      status: row.adGroup.status,
      type: row.adGroup.type || '',
      cpcBidMicros: row.adGroup.cpcBidMicros || null
    };
  },

  ads: function(row) {
    var ad = row.adGroupAd;
    var policyTopics = null;
    if (ad.policySummary && ad.policySummary.policyTopicEntries) {
      policyTopics = ad.policySummary.policyTopicEntries.map(function(e) {
        return { topic: e.topic || '', type: e.type || '' };
      });
    }
    return {
      adId: ad.ad.id,
      adGroupId: row.adGroup.id,
      adType: ad.ad.type,
      status: ad.status,
      approvalStatus: ad.policySummary ? ad.policySummary.approvalStatus : '',
      reviewStatus: ad.policySummary ? ad.policySummary.reviewStatus : '',
      adStrength: ad.adStrength || '',
      policyTopics: policyTopics,
      finalUrls: ad.ad.finalUrls || []
    };
  },

  assets: function(row) {
    var a = row.asset;
    return {
      assetId: a.id,
      name: a.name || '',
      assetType: a.type,
      textContent: a.textAsset ? a.textAsset.text : null,
      imageUrl: a.imageAsset && a.imageAsset.fullSize ? a.imageAsset.fullSize.url : null,
      imageWidth: a.imageAsset && a.imageAsset.fullSize ? a.imageAsset.fullSize.widthPixels : null,
      imageHeight: a.imageAsset && a.imageAsset.fullSize ? a.imageAsset.fullSize.heightPixels : null,
      youtubeVideoId: a.youtubeVideoAsset ? a.youtubeVideoAsset.youtubeVideoId : null,
      sitelinkText: a.sitelinkAsset ? a.sitelinkAsset.linkText : null,
      sitelinkDesc1: a.sitelinkAsset ? a.sitelinkAsset.description1 : null,
      sitelinkDesc2: a.sitelinkAsset ? a.sitelinkAsset.description2 : null,
      calloutText: a.calloutAsset ? a.calloutAsset.calloutText : null,
      snippetHeader: a.structuredSnippetAsset ? a.structuredSnippetAsset.header : null,
      snippetValues: a.structuredSnippetAsset ? a.structuredSnippetAsset.values : null,
      phoneNumber: a.callAsset ? a.callAsset.phoneNumber : null,
      globalApproval: a.policySummary ? a.policySummary.approvalStatus : '',
      globalReview: a.policySummary ? a.policySummary.reviewStatus : '',
      globalPolicyTopics: a.policySummary ? a.policySummary.policyTopicEntries : null
    };
  },

  customer_asset: function(row) {
    return {
      linkLevel: 'CUSTOMER',
      assetId: row.asset.id,
      fieldType: row.customerAsset.fieldType,
      linkStatus: row.customerAsset.status,
      approvalStatus: row.asset.policySummary ? row.asset.policySummary.approvalStatus : '',
      reviewStatus: row.asset.policySummary ? row.asset.policySummary.reviewStatus : '',
      primaryStatus: row.customerAsset.primaryStatus || '',
      primaryStatusReasons: row.customerAsset.primaryStatusReasons || [],
      policyTopics: row.asset.policySummary ? row.asset.policySummary.policyTopicEntries : null
    };
  },

  campaign_asset: function(row) {
    return {
      linkLevel: 'CAMPAIGN',
      assetId: row.asset.id,
      fieldType: row.campaignAsset.fieldType,
      campaignId: row.campaign.id,
      linkStatus: row.campaignAsset.status,
      approvalStatus: row.asset.policySummary ? row.asset.policySummary.approvalStatus : '',
      reviewStatus: row.asset.policySummary ? row.asset.policySummary.reviewStatus : '',
      primaryStatus: row.campaignAsset.primaryStatus || '',
      primaryStatusReasons: row.campaignAsset.primaryStatusReasons || [],
      policyTopics: row.asset.policySummary ? row.asset.policySummary.policyTopicEntries : null
    };
  },

  ad_group_asset: function(row) {
    return {
      linkLevel: 'AD_GROUP',
      assetId: row.asset.id,
      fieldType: row.adGroupAsset.fieldType,
      campaignId: row.campaign.id,
      adGroupId: row.adGroup.id,
      linkStatus: row.adGroupAsset.status,
      approvalStatus: row.asset.policySummary ? row.asset.policySummary.approvalStatus : '',
      reviewStatus: row.asset.policySummary ? row.asset.policySummary.reviewStatus : '',
      primaryStatus: row.adGroupAsset.primaryStatus || '',
      primaryStatusReasons: row.adGroupAsset.primaryStatusReasons || [],
      policyTopics: row.asset.policySummary ? row.asset.policySummary.policyTopicEntries : null
    };
  },

  ad_group_ad_asset_view: function(row) {
    var view = row.adGroupAdAssetView;
    var policySummary = view.policySummary || {};
    return {
      linkLevel: 'AD',
      assetId: row.asset.id,
      fieldType: view.fieldType,
      campaignId: row.campaign.id,
      adGroupId: row.adGroup.id,
      adId: row.adGroupAd.ad.id,
      approvalStatus: policySummary.approvalStatus || '',
      reviewStatus: policySummary.reviewStatus || '',
      linkStatus: 'ENABLED',
      isEnabled: view.enabled || false,
      performanceLabel: view.performanceLabel || '',
      pinnedField: view.pinnedField || '',
      assetSource: view.source || '',
      policyTopics: policySummary.policyTopicEntries || null
    };
  }
};

// Asset link resource types that go into the asset_links table
var ASSET_LINK_TYPES = ['customer_asset', 'campaign_asset', 'ad_group_asset', 'ad_group_ad_asset_view'];
```

- [ ] **Step 2: Commit**

```bash
git add scripts/ad-asset-policy-monitor/main.js
git commit -m "feat: add row transformer functions for all 9 resource types"
```

---

### Task 3: Add the `main()` function (single account first)

**Files:**
- Modify: `scripts/ad-asset-policy-monitor/main.js`

- [ ] **Step 1: Add the main function for single-account mode**

Append to `main.js`:

```javascript
// ─── MAIN ───────────────────────────────────────────────────────

function main() {
  var syncId = generateUuid_();
  var customerId = AdsApp.currentAccount().getCustomerId();

  Logger.log('Starting sync ' + syncId + ' for ' + customerId);

  // Process each resource type
  for (var resourceType in QUERIES) {
    Logger.log('Pulling ' + resourceType + '...');
    var rawRows = pullResource_(QUERIES[resourceType]);
    Logger.log('  → ' + rawRows.length + ' rows');

    if (rawRows.length === 0) continue;

    var transformer = TRANSFORMERS[resourceType];
    var transformedRows = [];
    for (var i = 0; i < rawRows.length; i++) {
      try {
        transformedRows.push(transformer(rawRows[i]));
      } catch (e) {
        Logger.log('  Transform error on row ' + i + ': ' + e.message);
      }
    }

    // Asset link types all go to the same RPC
    var targetType = ASSET_LINK_TYPES.indexOf(resourceType) >= 0 ? 'asset_links' : resourceType;
    pushToSupabase_(syncId, customerId, targetType, transformedRows);
  }

  // Finalize: deletion detection + cascade refresh
  finalize_(syncId, customerId);

  Logger.log('Sync ' + syncId + ' complete.');
}
```

- [ ] **Step 2: Commit**

```bash
git add scripts/ad-asset-policy-monitor/main.js
git commit -m "feat: add main() function for single-account sync"
```

---

### Task 4: Deploy Edge Function and run the script against a real account

**Files:** None (manual deployment and testing)

- [ ] **Step 1: Set Edge Function env vars in Supabase Dashboard**

Go to Supabase Dashboard → Edge Functions → `ingest-gads` → Settings:
- `ALLOWED_EMAILS`: your Google account email (the one that runs the Ads Script)

- [ ] **Step 2: Deploy the Edge Function**

```bash
supabase functions deploy ingest-gads
```

- [ ] **Step 3: Push migrations to production**

```bash
supabase db push
```

- [ ] **Step 4: Create the Google Ads Script**

1. Go to Google Ads → Tools → Bulk actions → Scripts
2. Click `+` to create a new script
3. Paste the contents of `scripts/ad-asset-policy-monitor/main.js`
4. Update `EDGE_FUNCTION_URL` with your production Edge Function URL
5. Save and authorize

- [ ] **Step 5: Run the script manually**

Click "Preview" or "Run" in the Google Ads Script editor. Watch the logs.

Expected:
- Logs show each resource type being pulled with row counts
- No `PUSH FAILED` errors
- Final line: `Sync {uuid} complete.`

- [ ] **Step 6: Verify data in Supabase**

```sql
-- Check data arrived
SELECT count(*) FROM ads.campaigns;
SELECT count(*) FROM ads.ad_groups;
SELECT count(*) FROM ads.ads;
SELECT count(*) FROM ads.assets;
SELECT count(*) FROM ads.asset_links;

-- Check the cascade view
SELECT * FROM ads.cascade_status ORDER BY impact_level;

-- Check sync run
SELECT * FROM ads.sync_runs ORDER BY started_at DESC LIMIT 1;
```

- [ ] **Step 7: Run the script a second time to verify change detection**

Run the script again. This time, the UPSERT should find existing rows and update them. Check:

```sql
-- If nothing changed in Google Ads, status_changes should be empty (or unchanged)
SELECT count(*) FROM ads.status_changes;
```

Expected: 0 new status changes (unless something actually changed in Google Ads between runs).

- [ ] **Step 8: Commit the final script**

```bash
git add scripts/ad-asset-policy-monitor/
git commit -m "feat: complete Google Ads Script for single-account sync"
```

---

### Task 5: Add MCC multi-account support

**Files:**
- Create: `scripts/ad-asset-policy-monitor/main-mcc.js`

- [ ] **Step 1: Write the MCC version**

```javascript
// scripts/ad-asset-policy-monitor/main-mcc.js
// Copy all QUERIES, TRANSFORMERS, helpers from main.js, then replace main():

function main() {
  var accounts = AdsManagerApp.accounts()
    .withCondition('customer_client.status = ENABLED')
    .get();

  while (accounts.hasNext()) {
    var account = accounts.next();
    AdsManagerApp.select(account);
    var customerId = AdsApp.currentAccount().getCustomerId();

    Logger.log('=== Processing account: ' + customerId + ' ===');

    try {
      processAccount_(customerId);
    } catch (e) {
      Logger.log('ACCOUNT FAILED [' + customerId + ']: ' + e.message);
    }
  }
}

function processAccount_(customerId) {
  var syncId = generateUuid_();
  Logger.log('Sync ' + syncId + ' for ' + customerId);

  for (var resourceType in QUERIES) {
    Logger.log('  Pulling ' + resourceType + '...');
    var rawRows = pullResource_(QUERIES[resourceType]);
    Logger.log('    → ' + rawRows.length + ' rows');

    if (rawRows.length === 0) continue;

    var transformer = TRANSFORMERS[resourceType];
    var transformedRows = [];
    for (var i = 0; i < rawRows.length; i++) {
      try {
        transformedRows.push(transformer(rawRows[i]));
      } catch (e) {
        Logger.log('    Transform error on row ' + i + ': ' + e.message);
      }
    }

    var targetType = ASSET_LINK_TYPES.indexOf(resourceType) >= 0 ? 'asset_links' : resourceType;
    pushToSupabase_(syncId, customerId, targetType, transformedRows);
  }

  finalize_(syncId, customerId);
  Logger.log('Sync ' + syncId + ' complete for ' + customerId);
}

// ... all QUERIES, TRANSFORMERS, helpers copied from main.js ...
```

- [ ] **Step 2: Commit**

```bash
git add scripts/ad-asset-policy-monitor/
git commit -m "feat: add MCC multi-account version of Google Ads Script"
```

---

## Phase 4 Definition of Done

- [ ] Google Ads Script runs manually against a real single account
- [ ] All 9 resource types are pulled and pushed to Supabase
- [ ] Data appears correctly in all dimension/fact tables
- [ ] Cascade view shows real disapprovals with correct impact levels
- [ ] Second run produces no false status changes
- [ ] MCC version iterates multiple accounts
- [ ] All code committed
