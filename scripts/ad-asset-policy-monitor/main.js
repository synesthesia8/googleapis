/**
 * Google Ads Asset Policy Monitor — Single Account Script
 *
 * Pulls all hierarchy data (campaigns, ad groups, ads, assets, asset links)
 * from a single Google Ads account and pushes it to a Supabase Edge Function
 * for storage, change detection, and cascade impact analysis.
 *
 * Setup:
 *   1. Create a new Google Ads Script (Tools > Bulk actions > Scripts)
 *   2. Paste this entire file. Save and authorise.
 *   3. Run once manually via "Preview", check Supabase for data.
 *   4. Schedule hourly once verified.
 */

// ─── CONFIG ─────────────────────────────────────────────────────────────────

var EDGE_FUNCTION_URL = 'https://makglpeikfgyugngywmc.supabase.co/functions/v1/ingest-gads';
var INGEST_API_KEY = '2cf86282f6a38fdabadb81274d57b0cfaf4be274029d84cf183e7dd2ae4fb62e';
var SUPABASE_ANON_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im1ha2dscGVpa2ZneXVnbmd5d21jIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzUwMzQyMTIsImV4cCI6MjA5MDYxMDIxMn0.icUPQTdBotmg8hMo2yNmZIrOiBhA32R7nZ8PjPyrB8M';
var BATCH_SIZE = 200;

// ─── GAQL QUERIES (Attributes only — no metrics) ────────────────────────────

var QUERIES = {
  accounts: [
    'SELECT',
    '  customer.id,',
    '  customer.descriptive_name',
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
    '  campaign.id',
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
    '  campaign.id',
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
    '  campaign.status,',
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
    '  campaign.status,',
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

// ─── ROW TRANSFORMERS ───────────────────────────────────────────────────────
// Map Google Ads JS objects → flat JSON matching our RPC function param names

var TRANSFORMERS = {
  accounts: function(row) {
    return {
      descriptiveName: row.customer.descriptiveName || ''
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
      endDate: c.endDate || null
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
      policyTopics = [];
      for (var i = 0; i < ad.policySummary.policyTopicEntries.length; i++) {
        var entry = ad.policySummary.policyTopicEntries[i];
        policyTopics.push({ topic: entry.topic || '', type: entry.type || '' });
      }
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

// ─── HELPERS ────────────────────────────────────────────────────────────────

function generateUuid_() {
  return Utilities.getUuid();
}

function getAuthHeaders_() {
  return {
    'Authorization': 'Bearer ' + SUPABASE_ANON_KEY,
    'x-api-key': INGEST_API_KEY
  };
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

function pushToSupabase_(syncId, customerId, resourceType, rows) {
  for (var i = 0; i < rows.length; i += BATCH_SIZE) {
    var batch = rows.slice(i, i + BATCH_SIZE);
    var response = UrlFetchApp.fetch(EDGE_FUNCTION_URL, {
      method: 'post',
      contentType: 'application/json',
      headers: getAuthHeaders_(),
      muteHttpExceptions: true,
      payload: JSON.stringify({
        sync_id: syncId,
        customer_id: customerId,
        resource_type: resourceType,
        batch_index: Math.floor(i / BATCH_SIZE),
        rows: batch
      })
    });
    var code = response.getResponseCode();
    if (code !== 200) {
      Logger.log('PUSH FAILED [' + resourceType + ' batch ' + Math.floor(i / BATCH_SIZE) + ']: HTTP ' + code + ' — ' + response.getContentText());
    }
  }
}

function finalize_(syncId, customerId) {
  var response = UrlFetchApp.fetch(EDGE_FUNCTION_URL, {
    method: 'post',
    contentType: 'application/json',
    headers: getAuthHeaders_(),
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

function createSyncRun_(syncId, customerId) {
  var response = UrlFetchApp.fetch(EDGE_FUNCTION_URL, {
    method: 'post',
    contentType: 'application/json',
    headers: getAuthHeaders_(),
    muteHttpExceptions: true,
    payload: JSON.stringify({
      sync_id: syncId,
      customer_id: customerId,
      resource_type: 'create_sync_run',
      rows: []
    })
  });
  if (response.getResponseCode() !== 200) {
    Logger.log('CREATE SYNC RUN FAILED: ' + response.getContentText());
  }
}

// ─── MAIN ───────────────────────────────────────────────────────────────────

function main() {
  var syncId = generateUuid_();
  var customerId = AdsApp.currentAccount().getCustomerId();

  Logger.log('Starting sync ' + syncId + ' for CID ' + customerId);

  var totalRows = 0;

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
    totalRows += transformedRows.length;
  }

  // Create sync run record, then finalize
  createSyncRun_(syncId, customerId);
  finalize_(syncId, customerId);

  Logger.log('Sync ' + syncId + ' complete. Total rows: ' + totalRows);
}
