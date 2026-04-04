/**
 * Google Ads Asset Policy Monitor v3 — Secured
 *
 * Same as v2 (pulls everything, stores raw, no transformation)
 * with RLS enabled on all tables, verify_jwt disabled, no anon key needed.
 *
 * Setup:
 *   1. Create a new Google Ads Script (Tools > Bulk actions > Scripts)
 *   2. Paste this entire file. Save and authorise.
 *   3. Run once manually via "Preview", check Supabase for data.
 *   4. Schedule hourly once verified.
 */

// ─── CONFIG ─────────────────────────────────────────────────────────────────

var EDGE_FUNCTION_URL = 'https://makglpeikfgyugngywmc.supabase.co/functions/v1/ingest-gads-v3';
var INGEST_API_KEY = '2cf86282f6a38fdabadb81274d57b0cfaf4be274029d84cf183e7dd2ae4fb62e';
var BATCH_SIZE = 200;

// ─── GAQL QUERIES — PULL EVERYTHING ─────────────────────────────────────────

var QUERIES = {
  accounts: [
    'SELECT',
    '  customer.resource_name,',
    '  customer.id,',
    '  customer.descriptive_name,',
    '  customer.currency_code,',
    '  customer.time_zone,',
    '  customer.tracking_url_template,',
    '  customer.final_url_suffix,',
    '  customer.auto_tagging_enabled,',
    '  customer.has_partners_badge,',
    '  customer.manager,',
    '  customer.test_account,',
    '  customer.optimization_score,',
    '  customer.optimization_score_weight,',
    '  customer.status',
    'FROM customer'
  ].join('\n'),

  campaigns: [
    'SELECT',
    '  campaign.resource_name,',
    '  campaign.id,',
    '  campaign.name,',
    '  campaign.status,',
    '  campaign.primary_status,',
    '  campaign.primary_status_reasons,',
    '  campaign.serving_status,',
    '  campaign.advertising_channel_type,',
    '  campaign.advertising_channel_sub_type,',
    '  campaign.experiment_type,',
    '  campaign.ad_serving_optimization_status,',
    '  campaign.bidding_strategy_type,',
    '  campaign.bidding_strategy_system_status,',
    '  campaign.start_date,',
    '  campaign.end_date,',
    '  campaign.campaign_budget,',
    '  campaign.campaign_group,',
    '  campaign.labels,',
    '  campaign.tracking_url_template,',
    '  campaign.final_url_suffix,',
    '  campaign.url_custom_parameters,',
    '  campaign.optimization_score,',
    '  campaign.keyword_match_type,',
    '  campaign.listing_type,',
    '  campaign.network_settings.target_google_search,',
    '  campaign.network_settings.target_search_network,',
    '  campaign.network_settings.target_content_network,',
    '  campaign.network_settings.target_partner_search_network,',
    '  campaign.network_settings.target_youtube,',
    '  campaign.network_settings.target_google_tv_network,',
    '  campaign.geo_target_type_setting.positive_geo_target_type,',
    '  campaign.geo_target_type_setting.negative_geo_target_type,',
    '  campaign.excluded_parent_asset_field_types,',
    '  campaign.excluded_parent_asset_set_types,',
    '  campaign.payment_mode,',
    '  campaign.video_brand_safety_suitability,',
    '  campaign.contains_eu_political_advertising,',
    '  campaign.missing_eu_political_advertising_declaration,',
    '  campaign.brand_guidelines_enabled,',
    '  campaign.asset_automation_settings',
    'FROM campaign'
  ].join('\n'),

  ad_groups: [
    'SELECT',
    '  ad_group.resource_name,',
    '  ad_group.id,',
    '  ad_group.name,',
    '  ad_group.status,',
    '  ad_group.type,',
    '  ad_group.primary_status,',
    '  ad_group.primary_status_reasons,',
    '  ad_group.ad_rotation_mode,',
    '  ad_group.base_ad_group,',
    '  ad_group.tracking_url_template,',
    '  ad_group.url_custom_parameters,',
    '  ad_group.campaign,',
    '  ad_group.cpc_bid_micros,',
    '  ad_group.effective_cpc_bid_micros,',
    '  ad_group.cpm_bid_micros,',
    '  ad_group.target_cpa_micros,',
    '  ad_group.cpv_bid_micros,',
    '  ad_group.target_cpm_micros,',
    '  ad_group.target_roas,',
    '  ad_group.percent_cpc_bid_micros,',
    '  ad_group.fixed_cpm_micros,',
    '  ad_group.target_cpv_micros,',
    '  ad_group.target_cpc_micros,',
    '  ad_group.optimized_targeting_enabled,',
    '  ad_group.display_custom_bid_dimension,',
    '  ad_group.final_url_suffix,',
    '  ad_group.effective_target_cpa_micros,',
    '  ad_group.effective_target_cpa_source,',
    '  ad_group.effective_target_roas,',
    '  ad_group.effective_target_roas_source,',
    '  ad_group.labels,',
    '  ad_group.excluded_parent_asset_field_types,',
    '  ad_group.excluded_parent_asset_set_types,',
    '  campaign.id,',
    '  campaign.name',
    'FROM ad_group'
  ].join('\n'),

  ads: [
    'SELECT',
    '  ad_group_ad.resource_name,',
    '  ad_group_ad.status,',
    '  ad_group_ad.ad.id,',
    '  ad_group_ad.ad.type,',
    '  ad_group_ad.ad.name,',
    '  ad_group_ad.ad.final_urls,',
    '  ad_group_ad.ad.final_mobile_urls,',
    '  ad_group_ad.ad.tracking_url_template,',
    '  ad_group_ad.ad.final_url_suffix,',
    '  ad_group_ad.policy_summary.approval_status,',
    '  ad_group_ad.policy_summary.review_status,',
    '  ad_group_ad.policy_summary.policy_topic_entries,',
    '  ad_group_ad.ad_strength,',
    '  ad_group_ad.action_items,',
    '  ad_group_ad.labels,',
    '  ad_group_ad.primary_status,',
    '  ad_group_ad.primary_status_reasons,',
    '  ad_group_ad.ad.responsive_search_ad.headlines,',
    '  ad_group_ad.ad.responsive_search_ad.descriptions,',
    '  ad_group_ad.ad.responsive_search_ad.path1,',
    '  ad_group_ad.ad.responsive_search_ad.path2,',
    '  ad_group.id,',
    '  ad_group.name,',
    '  campaign.id,',
    '  campaign.name',
    'FROM ad_group_ad'
  ].join('\n'),

  assets: [
    'SELECT',
    '  asset.resource_name,',
    '  asset.id,',
    '  asset.name,',
    '  asset.type,',
    '  asset.source,',
    '  asset.final_urls,',
    '  asset.final_mobile_urls,',
    '  asset.tracking_url_template,',
    '  asset.url_custom_parameters,',
    '  asset.final_url_suffix,',
    '  asset.policy_summary.approval_status,',
    '  asset.policy_summary.review_status,',
    '  asset.policy_summary.policy_topic_entries,',
    '  asset.field_type_policy_summaries,',
    '  asset.text_asset.text,',
    '  asset.image_asset.full_size.url,',
    '  asset.image_asset.full_size.width_pixels,',
    '  asset.image_asset.full_size.height_pixels,',
    '  asset.image_asset.mime_type,',
    '  asset.youtube_video_asset.youtube_video_id,',
    '  asset.youtube_video_asset.youtube_video_title,',
    '  asset.sitelink_asset.description1,',
    '  asset.sitelink_asset.description2,',
    '  asset.sitelink_asset.link_text,',
    '  asset.callout_asset.callout_text,',
    '  asset.structured_snippet_asset.header,',
    '  asset.structured_snippet_asset.values,',
    '  asset.call_asset.phone_number,',
    '  asset.call_asset.country_code,',
    '  asset.promotion_asset.promotion_target,',
    '  asset.price_asset.type,',
    '  asset.lead_form_asset.business_name,',
    '  asset.call_to_action_asset.call_to_action,',
    '  asset.mobile_app_asset.app_id,',
    '  asset.mobile_app_asset.app_store,',
    '  asset.hotel_callout_asset.text,',
    '  asset.page_feed_asset.page_url,',
    '  asset.page_feed_asset.labels',
    'FROM asset'
  ].join('\n'),

  customer_assets: [
    'SELECT',
    '  customer_asset.resource_name,',
    '  customer_asset.asset,',
    '  customer_asset.field_type,',
    '  customer_asset.source,',
    '  customer_asset.status,',
    '  customer_asset.primary_status,',
    '  customer_asset.primary_status_details,',
    '  customer_asset.primary_status_reasons,',
    '  asset.id,',
    '  asset.name,',
    '  asset.type,',
    '  asset.policy_summary.approval_status,',
    '  asset.policy_summary.review_status,',
    '  asset.policy_summary.policy_topic_entries',
    'FROM customer_asset'
  ].join('\n'),

  campaign_assets: [
    'SELECT',
    '  campaign_asset.resource_name,',
    '  campaign_asset.campaign,',
    '  campaign_asset.asset,',
    '  campaign_asset.field_type,',
    '  campaign_asset.source,',
    '  campaign_asset.status,',
    '  campaign_asset.primary_status,',
    '  campaign_asset.primary_status_details,',
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
    'FROM campaign_asset'
  ].join('\n'),

  ad_group_assets: [
    'SELECT',
    '  ad_group_asset.resource_name,',
    '  ad_group_asset.ad_group,',
    '  ad_group_asset.asset,',
    '  ad_group_asset.field_type,',
    '  ad_group_asset.source,',
    '  ad_group_asset.status,',
    '  ad_group_asset.primary_status,',
    '  ad_group_asset.primary_status_details,',
    '  ad_group_asset.primary_status_reasons,',
    '  ad_group.id,',
    '  ad_group.name,',
    '  ad_group.status,',
    '  campaign.id,',
    '  campaign.name,',
    '  campaign.status,',
    '  asset.id,',
    '  asset.name,',
    '  asset.type,',
    '  asset.policy_summary.approval_status,',
    '  asset.policy_summary.review_status,',
    '  asset.policy_summary.policy_topic_entries',
    'FROM ad_group_asset'
  ].join('\n'),

  ad_group_ad_asset_view: [
    'SELECT',
    '  ad_group_ad_asset_view.resource_name,',
    '  ad_group_ad_asset_view.ad_group_ad,',
    '  ad_group_ad_asset_view.asset,',
    '  ad_group_ad_asset_view.field_type,',
    '  ad_group_ad_asset_view.enabled,',
    '  ad_group_ad_asset_view.policy_summary,',
    '  ad_group_ad_asset_view.performance_label,',
    '  ad_group_ad_asset_view.pinned_field,',
    '  ad_group_ad_asset_view.source,',
    '  ad_group_ad.ad.id,',
    '  ad_group_ad.ad.type,',
    '  ad_group_ad.status,',
    '  ad_group_ad.policy_summary.approval_status,',
    '  ad_group_ad.policy_summary.review_status,',
    '  ad_group.id,',
    '  ad_group.name,',
    '  campaign.id,',
    '  campaign.name,',
    '  campaign.status,',
    '  asset.id,',
    '  asset.name,',
    '  asset.type,',
    '  asset.policy_summary.approval_status,',
    '  asset.policy_summary.review_status',
    'FROM ad_group_ad_asset_view'
  ].join('\n')
};

// ─── HELPERS ────────────────────────────────────────────────────────────────

function generateUuid_() {
  return Utilities.getUuid();
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

function pushToSupabase_(pullId, customerId, resourceType, rows, errors) {
  var pushed = 0;
  for (var i = 0; i < rows.length; i += BATCH_SIZE) {
    var batch = rows.slice(i, i + BATCH_SIZE);
    var response = UrlFetchApp.fetch(EDGE_FUNCTION_URL, {
      method: 'post',
      contentType: 'application/json',
      headers: { 'x-api-key': INGEST_API_KEY },
      muteHttpExceptions: true,
      payload: JSON.stringify({
        pull_id: pullId,
        customer_id: customerId,
        resource_type: resourceType,
        rows: batch
      })
    });
    var code = response.getResponseCode();
    if (code !== 200) {
      var msg = response.getContentText();
      Logger.log('PUSH FAILED [' + resourceType + ' batch ' + Math.floor(i / BATCH_SIZE) + ']: HTTP ' + code + ' — ' + msg);
      errors.push({
        resource: resourceType,
        batch: Math.floor(i / BATCH_SIZE),
        code: code,
        message: msg.substring(0, 200)
      });
    } else {
      pushed += batch.length;
    }
  }
  return pushed;
}

function startPull_(pullId, customerId) {
  var response = UrlFetchApp.fetch(EDGE_FUNCTION_URL, {
    method: 'post',
    contentType: 'application/json',
    headers: { 'x-api-key': INGEST_API_KEY },
    muteHttpExceptions: true,
    payload: JSON.stringify({
      pull_id: pullId,
      customer_id: customerId,
      resource_type: 'start_pull',
      rows: []
    })
  });
  if (response.getResponseCode() !== 200) {
    Logger.log('START PULL FAILED: ' + response.getContentText());
  }
}

function completePull_(pullId, customerId, results, errors) {
  var response = UrlFetchApp.fetch(EDGE_FUNCTION_URL, {
    method: 'post',
    contentType: 'application/json',
    headers: { 'x-api-key': INGEST_API_KEY },
    muteHttpExceptions: true,
    payload: JSON.stringify({
      pull_id: pullId,
      customer_id: customerId,
      resource_type: 'complete_pull',
      results: results,
      errors: errors.length > 0 ? errors : null,
      rows: []
    })
  });
  if (response.getResponseCode() !== 200) {
    Logger.log('COMPLETE PULL FAILED: ' + response.getContentText());
  }
}

// ─── MAIN ───────────────────────────────────────────────────────────────────

function main() {
  var pullId = generateUuid_();
  var customerId = AdsApp.currentAccount().getCustomerId();
  var results = {};
  var errors = [];

  Logger.log('v3 pull ' + pullId + ' for CID ' + customerId);

  // Register pull as running
  startPull_(pullId, customerId);

  for (var resourceType in QUERIES) {
    Logger.log('Pulling ' + resourceType + '...');
    var rows = pullResource_(QUERIES[resourceType]);
    Logger.log('  → ' + rows.length + ' rows');

    results[resourceType] = rows.length;

    if (rows.length > 0) {
      pushToSupabase_(pullId, customerId, resourceType, rows, errors);
    }
  }

  // Complete pull with results
  completePull_(pullId, customerId, results, errors);

  Logger.log('v3 pull ' + pullId + ' complete. Errors: ' + errors.length);
}
