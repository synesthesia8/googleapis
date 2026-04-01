/**
 * Ad Asset Disapproval Tracker — Google Ads Script
 *
 * Pulls all non-approved assets within ads via the ad_group_ad_asset_view
 * resource, writes the current snapshot to a Google Sheet, and diffs against
 * the previous snapshot to detect new, changed, and resolved asset
 * disapprovals. Changes are appended to a persistent CHANGES log tab.
 *
 * This script answers: "Which specific asset inside which specific ad is
 * causing the ad not to serve, and what is the policy violation?"
 *
 * Supported ad types: Responsive Search Ads, App Ads, Demand Gen.
 * NOT supported: Responsive Display Ads.
 *
 * Setup:
 *   1. Create a new Google Sheet and paste its URL into SPREADSHEET_URL below.
 *   2. Create a new Google Ads Script (Tools > Bulk actions > Scripts).
 *   3. Paste this entire file. Save and authorise.
 *   4. Run once manually, then schedule hourly.
 */

// ─── CONFIG ─────────────────────────────────────────────────────────────────

var CONFIG = {
  SPREADSHEET_URL:     'YOUR_SPREADSHEET_URL_HERE',
  SHEET_AD_ASSETS:     'Ad Assets',
  SHEET_CHANGES:       'Changes',
  SHEET_SNAPSHOT:      '_Snapshot',
  SHEET_DASHBOARD:     'Dashboard'
};

// ─── GAQL ───────────────────────────────────────────────────────────────────

var GAQL_NON_APPROVED_AD_ASSETS = [
  'SELECT',
  '  campaign.id,',
  '  campaign.name,',
  '  ad_group.id,',
  '  ad_group.name,',
  '  ad_group_ad.ad.id,',
  '  ad_group_ad.ad.type,',
  '  ad_group_ad.status,',
  '  ad_group_ad.policy_summary.approval_status,',
  '  ad_group_ad_asset_view.field_type,',
  '  ad_group_ad_asset_view.enabled,',
  '  ad_group_ad_asset_view.performance_label,',
  '  ad_group_ad_asset_view.pinned_field,',
  '  ad_group_ad_asset_view.source,',
  '  ad_group_ad_asset_view.policy_summary,',
  '  asset.id,',
  '  asset.name,',
  '  asset.type,',
  '  asset.policy_summary.approval_status,',
  '  asset.policy_summary.review_status',
  'FROM ad_group_ad_asset_view',
  'WHERE ad_group_ad_asset_view.enabled = TRUE',
  '  AND ad_group_ad.status != \'REMOVED\''
].join('\n');

// ─── COLUMN DEFINITIONS ────────────────────────────────────────────────────
// Ordered: Ad Identification → Asset Identification → Asset Verdict → Ad Context

var COLUMNS = [
  'Campaign',
  'Campaign ID',
  'Ad Group',
  'Ad Group ID',
  'Ad ID',
  'Ad Type',
  'Asset ID',
  'Asset Name',
  'Asset Type',
  'Field Type',
  'Pinned Field',
  'Asset Source',
  'Performance Label',
  'Asset Approval Status',
  'Asset Review Status',
  'Policy Topics',
  'Policy Types',
  'Policy Evidence',
  'Ad Status',
  'Ad Approval Status',
  'Asset Global Approval',
  'Asset Global Review'
];

// ─── ENTRY POINT ────────────────────────────────────────────────────────────

function main() {
  var ss = SpreadsheetApp.openByUrl(CONFIG.SPREADSHEET_URL);

  var currentRows = fetchNonApprovedAdAssets_();
  var previousMap = loadSnapshot_(ss);

  var currentMap = buildKeyedMap_(currentRows);
  var diff       = computeDiff_(previousMap, currentMap);

  writeAdAssetsSheet_(ss, currentRows);
  writeChangesSheet_(ss, diff);
  writeDashboard_(ss, currentRows, diff);
  saveSnapshot_(ss, currentMap);

  Logger.log('Done. Ad Assets: ' + currentRows.length +
             ', New: ' + diff.added.length +
             ', Changed: ' + diff.changed.length +
             ', Resolved: ' + diff.resolved.length);
}

// ─── DATA FETCH ─────────────────────────────────────────────────────────────

function fetchNonApprovedAdAssets_() {
  var rows = [];
  var report = AdsApp.search(GAQL_NON_APPROVED_AD_ASSETS);

  while (report.hasNext()) {
    var row = report.next();

    var campaign       = row.campaign;
    var adGroup        = row.adGroup;
    var adGroupAd      = row.adGroupAd;
    var ad             = adGroupAd.ad;
    var assetView      = row.adGroupAdAssetView;
    var assetViewPolicy = assetView.policySummary;
    var asset          = row.asset;

    if (!assetViewPolicy || assetViewPolicy.approvalStatus === 'APPROVED') {
      continue;
    }

    var policyTopics   = [];
    var policyTypes    = [];
    var policyEvidence = [];

    if (assetViewPolicy.policyTopicEntries) {
      for (var i = 0; i < assetViewPolicy.policyTopicEntries.length; i++) {
        var entry = assetViewPolicy.policyTopicEntries[i];
        policyTopics.push(entry.topic || '');
        policyTypes.push(entry.type || '');
        policyEvidence.push(extractEvidence_(entry));
      }
    }

    rows.push([
      campaign.name,                                        // 0  Campaign
      campaign.id,                                          // 1  Campaign ID
      adGroup.name,                                         // 2  Ad Group
      adGroup.id,                                           // 3  Ad Group ID
      ad.id,                                                // 4  Ad ID
      ad.type,                                              // 5  Ad Type
      asset.id,                                             // 6  Asset ID
      asset.name || '',                                     // 7  Asset Name
      asset.type,                                           // 8  Asset Type
      assetView.fieldType,                                  // 9  Field Type
      assetView.pinnedField || '',                          // 10 Pinned Field
      assetView.source || '',                               // 11 Asset Source
      assetView.performanceLabel || '',                     // 12 Performance Label
      assetViewPolicy.approvalStatus,                       // 13 Asset Approval Status
      assetViewPolicy.reviewStatus,                         // 14 Asset Review Status
      policyTopics.join(' | '),                             // 15 Policy Topics
      policyTypes.join(' | '),                              // 16 Policy Types
      policyEvidence.join(' | '),                           // 17 Policy Evidence
      adGroupAd.status,                                     // 18 Ad Status
      adGroupAd.policySummary.approvalStatus || '',         // 19 Ad Approval Status
      asset.policySummary ? asset.policySummary.approvalStatus || '' : '', // 20 Asset Global Approval
      asset.policySummary ? asset.policySummary.reviewStatus || '' : ''    // 21 Asset Global Review
    ]);
  }

  return rows;
}

function extractEvidence_(entry) {
  if (!entry.evidences || entry.evidences.length === 0) {
    return '';
  }

  var parts = [];
  for (var i = 0; i < entry.evidences.length; i++) {
    var ev = entry.evidences[i];
    if (ev.textList && ev.textList.texts) {
      parts.push('Text: ' + ev.textList.texts.join(', '));
    } else if (ev.websiteList && ev.websiteList.websites) {
      parts.push('Sites: ' + ev.websiteList.websites.join(', '));
    } else if (ev.destinationTextList && ev.destinationTextList.destinationTexts) {
      parts.push('Dest text: ' + ev.destinationTextList.destinationTexts.join(', '));
    } else if (ev.destinationNotWorking) {
      var dnw = ev.destinationNotWorking;
      var detail = dnw.expandedUrl || '';
      if (dnw.httpErrorCode) detail += ' (HTTP ' + dnw.httpErrorCode + ')';
      if (dnw.dnsErrorType) detail += ' (DNS: ' + dnw.dnsErrorType + ')';
      parts.push('Dest not working: ' + detail);
    } else if (ev.destinationMismatch) {
      parts.push('URL mismatch');
    } else if (ev.languageCode) {
      parts.push('Language: ' + ev.languageCode);
    }
  }
  return parts.join('; ');
}

// ─── SNAPSHOT DIFF ENGINE ───────────────────────────────────────────────────

function compositeKey_(row) {
  // campaign_id + ad_group_id + ad_id + asset_id + field_type
  return row[1] + '_' + row[3] + '_' + row[4] + '_' + row[6] + '_' + row[9];
}

function signatureValue_(row) {
  // asset_approval + asset_review + policy_topics + ad_approval
  return row[13] + '|' + row[14] + '|' + row[15] + '|' + row[19];
}

function buildKeyedMap_(rows) {
  var map = {};
  for (var i = 0; i < rows.length; i++) {
    var key = compositeKey_(rows[i]);
    map[key] = {
      row: rows[i],
      sig: signatureValue_(rows[i])
    };
  }
  return map;
}

function computeDiff_(previousMap, currentMap) {
  var now     = new Date();
  var ts      = Utilities.formatDate(now, AdsApp.currentAccount().getTimeZone(), 'yyyy-MM-dd HH:mm:ss');
  var added   = [];
  var changed = [];
  var resolved = [];

  for (var key in currentMap) {
    if (!previousMap[key]) {
      added.push(buildChangeRow_('NEW', ts, currentMap[key].row, null));
    } else if (previousMap[key].sig !== currentMap[key].sig) {
      changed.push(buildChangeRow_('CHANGED', ts, currentMap[key].row, previousMap[key].row));
    }
  }

  for (var key in previousMap) {
    if (!currentMap[key]) {
      resolved.push(buildChangeRow_('RESOLVED', ts, previousMap[key].row, null));
    }
  }

  return { added: added, changed: changed, resolved: resolved };
}

function buildChangeRow_(changeType, timestamp, currentRow, previousRow) {
  var row = [
    timestamp,          // 0
    changeType,         // 1
    currentRow[0],      // 2  Campaign
    currentRow[1],      // 3  Campaign ID
    currentRow[2],      // 4  Ad Group
    currentRow[3],      // 5  Ad Group ID
    currentRow[4],      // 6  Ad ID
    currentRow[6],      // 7  Asset ID
    currentRow[9],      // 8  Field Type
    currentRow[8],      // 9  Asset Type
    currentRow[13],     // 10 Asset Approval Status
    currentRow[14],     // 11 Asset Review Status
    currentRow[15]      // 12 Policy Topics
  ];

  if (changeType === 'CHANGED' && previousRow) {
    row.push(previousRow[13] + ' → ' + currentRow[13]); // Approval change
    row.push(previousRow[14] + ' → ' + currentRow[14]); // Review change
  } else {
    row.push('');
    row.push('');
  }

  return row;
}

// ─── SHEET WRITERS ──────────────────────────────────────────────────────────

function getOrCreateSheet_(ss, name) {
  var sheet = ss.getSheetByName(name);
  if (!sheet) {
    sheet = ss.insertSheet(name);
  }
  return sheet;
}

function writeAdAssetsSheet_(ss, rows) {
  var sheet = getOrCreateSheet_(ss, CONFIG.SHEET_AD_ASSETS);
  sheet.clearContents();

  sheet.getRange(1, 1, 1, COLUMNS.length).setValues([COLUMNS]).setFontWeight('bold');

  if (rows.length > 0) {
    sheet.getRange(2, 1, rows.length, COLUMNS.length).setValues(rows);
  }

  applyConditionalFormatting_(sheet, rows.length);
}

function applyConditionalFormatting_(sheet, rowCount) {
  sheet.clearConditionalFormatRules();
  if (rowCount === 0) return;

  var approvalCol = 14; // Asset Approval Status is column N (index 14)
  var approvalRange = sheet.getRange(2, approvalCol, Math.max(rowCount, 1), 1);
  var rules = sheet.getConditionalFormatRules();

  rules.push(SpreadsheetApp.newConditionalFormatRule()
    .whenTextEqualTo('DISAPPROVED')
    .setBackground('#f4cccc')
    .setFontColor('#990000')
    .setRanges([approvalRange])
    .build());

  rules.push(SpreadsheetApp.newConditionalFormatRule()
    .whenTextEqualTo('APPROVED_LIMITED')
    .setBackground('#fce5cd')
    .setFontColor('#b45f06')
    .setRanges([approvalRange])
    .build());

  rules.push(SpreadsheetApp.newConditionalFormatRule()
    .whenTextEqualTo('AREA_OF_INTEREST_ONLY')
    .setBackground('#fff2cc')
    .setFontColor('#bf9000')
    .setRanges([approvalRange])
    .build());

  sheet.setConditionalFormatRules(rules);
}

function writeChangesSheet_(ss, diff) {
  var sheet = getOrCreateSheet_(ss, CONFIG.SHEET_CHANGES);
  var changeHeader = [
    'Timestamp', 'Change Type', 'Campaign', 'Campaign ID',
    'Ad Group', 'Ad Group ID', 'Ad ID', 'Asset ID',
    'Field Type', 'Asset Type',
    'Approval Status', 'Review Status', 'Policy Topics',
    'Approval Change', 'Review Change'
  ];

  if (sheet.getLastRow() === 0) {
    sheet.getRange(1, 1, 1, changeHeader.length).setValues([changeHeader]).setFontWeight('bold');
  }

  var allChanges = diff.added.concat(diff.changed).concat(diff.resolved);
  if (allChanges.length > 0) {
    var startRow = sheet.getLastRow() + 1;
    sheet.getRange(startRow, 1, allChanges.length, changeHeader.length).setValues(allChanges);
  }
}

function writeDashboard_(ss, currentRows, diff) {
  var sheet = getOrCreateSheet_(ss, CONFIG.SHEET_DASHBOARD);
  sheet.clearContents();

  var now = Utilities.formatDate(new Date(), AdsApp.currentAccount().getTimeZone(), 'yyyy-MM-dd HH:mm:ss');

  var disapproved     = 0;
  var approvedLimited = 0;
  var areaOfInterest  = 0;
  var underReview     = 0;

  var byFieldType = {};
  var affectedAds = {};

  for (var i = 0; i < currentRows.length; i++) {
    var approval  = currentRows[i][13];
    var review    = currentRows[i][14];
    var fieldType = currentRows[i][9];
    var adKey     = currentRows[i][1] + '_' + currentRows[i][3] + '_' + currentRows[i][4];

    if (approval === 'DISAPPROVED') disapproved++;
    else if (approval === 'APPROVED_LIMITED') approvedLimited++;
    else if (approval === 'AREA_OF_INTEREST_ONLY') areaOfInterest++;
    if (review === 'REVIEW_IN_PROGRESS' || review === 'UNDER_APPEAL') underReview++;

    byFieldType[fieldType] = (byFieldType[fieldType] || 0) + 1;
    affectedAds[adKey] = true;
  }

  var data = [
    ['Ad Asset Disapproval Tracker — Dashboard', ''],
    ['Last Updated', now],
    ['', ''],
    ['CURRENT STATE', ''],
    ['Total Non-Approved Assets', currentRows.length],
    ['Unique Ads Affected', Object.keys(affectedAds).length],
    ['Disapproved', disapproved],
    ['Approved (Limited)', approvedLimited],
    ['Area of Interest Only', areaOfInterest],
    ['Under Review / Appeal', underReview],
    ['', ''],
    ['BREAKDOWN BY FIELD TYPE', '']
  ];

  var fieldTypes = Object.keys(byFieldType).sort();
  for (var j = 0; j < fieldTypes.length; j++) {
    data.push([fieldTypes[j], byFieldType[fieldTypes[j]]]);
  }

  data.push(['', '']);
  data.push(['CHANGES THIS RUN', '']);
  data.push(['New Disapprovals', diff.added.length]);
  data.push(['Status Changes', diff.changed.length]);
  data.push(['Resolved', diff.resolved.length]);

  sheet.getRange(1, 1, data.length, 2).setValues(data);

  sheet.getRange(1, 1).setFontSize(14).setFontWeight('bold');
  sheet.getRange(4, 1).setFontWeight('bold');
  sheet.getRange(12, 1).setFontWeight('bold');

  sheet.getRange(7, 1, 1, 2).setBackground('#f4cccc');
  sheet.getRange(8, 1, 1, 2).setBackground('#fce5cd');
  sheet.getRange(9, 1, 1, 2).setBackground('#fff2cc');

  var changesHeaderRow = data.length - 3;
  sheet.getRange(changesHeaderRow, 1).setFontWeight('bold');
  sheet.getRange(changesHeaderRow + 1, 1, 1, 2).setBackground('#f4cccc');
  sheet.getRange(changesHeaderRow + 3, 1, 1, 2).setBackground('#d9ead3');
}

// ─── SNAPSHOT PERSISTENCE ───────────────────────────────────────────────────

function saveSnapshot_(ss, keyedMap) {
  var sheet = getOrCreateSheet_(ss, CONFIG.SHEET_SNAPSHOT);
  sheet.clearContents();

  var snapshotRows = [];
  for (var key in keyedMap) {
    snapshotRows.push([key, keyedMap[key].sig, JSON.stringify(keyedMap[key].row)]);
  }

  if (snapshotRows.length > 0) {
    sheet.getRange(1, 1, snapshotRows.length, 3).setValues(snapshotRows);
  }
}

function loadSnapshot_(ss) {
  var sheet = ss.getSheetByName(CONFIG.SHEET_SNAPSHOT);
  if (!sheet || sheet.getLastRow() === 0) return {};

  var data = sheet.getDataRange().getValues();
  var map = {};

  for (var i = 0; i < data.length; i++) {
    var key = data[i][0];
    var sig = data[i][1];
    var row;
    try {
      row = JSON.parse(data[i][2]);
    } catch (e) {
      continue;
    }
    map[key] = { row: row, sig: sig };
  }

  return map;
}
