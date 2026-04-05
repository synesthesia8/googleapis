/**
 * Ad Disapproval Tracker — Google Ads Script (POC)
 *
 * Pulls all non-approved ads via GAQL, writes the current snapshot to a
 * Google Sheet, and diffs against the previous snapshot to detect new,
 * changed, and resolved disapprovals. Changes are appended to a persistent
 * CHANGES log tab.
 *
 * Setup:
 *   1. Create a new Google Sheet and paste its URL into SPREADSHEET_URL below.
 *   2. Create a new Google Ads Script (Tools > Bulk actions > Scripts).
 *   3. Paste this entire file. Save and authorise.
 *   4. Run once manually, then schedule hourly.
 */

// ─── CONFIG ─────────────────────────────────────────────────────────────────

var CONFIG = {
  SPREADSHEET_URL: 'YOUR_SPREADSHEET_URL_HERE',
  SHEET_ADS:       'Ads',
  SHEET_CHANGES:   'Changes',
  SHEET_SNAPSHOT:  '_Snapshot',
  SHEET_DASHBOARD: 'Dashboard'
};

// ─── GAQL ───────────────────────────────────────────────────────────────────

var GAQL_NON_APPROVED_ADS = [
  'SELECT',
  '  campaign.id,',
  '  campaign.name,',
  '  campaign.status,',
  '  ad_group.id,',
  '  ad_group.name,',
  '  ad_group.status,',
  '  ad_group_ad.ad.id,',
  '  ad_group_ad.ad.type,',
  '  ad_group_ad.ad.final_urls,',
  '  ad_group_ad.status,',
  '  ad_group_ad.primary_status,',
  '  ad_group_ad.primary_status_reasons,',
  '  ad_group_ad.policy_summary.approval_status,',
  '  ad_group_ad.policy_summary.review_status,',
  '  ad_group_ad.policy_summary.policy_topic_entries',
  'FROM ad_group_ad',
  'WHERE ad_group_ad.policy_summary.approval_status != \'APPROVED\'',
  '  AND ad_group_ad.status != \'REMOVED\''
].join('\n');

// ─── COLUMN DEFINITIONS ────────────────────────────────────────────────────
// Ordered: Identification → What → Verdict → Policy Detail

var COLUMNS = [
  'Campaign',
  'Campaign ID',
  'Ad Group',
  'Ad Group ID',
  'Ad ID',
  'Ad Type',
  'Final URL',
  'Ad Status',
  'Primary Status',
  'Primary Status Reasons',
  'Approval Status',
  'Review Status',
  'Policy Topics',
  'Policy Types',
  'Policy Evidence'
];

// ─── ENTRY POINT ────────────────────────────────────────────────────────────

function main() {
  var ss = SpreadsheetApp.openByUrl(CONFIG.SPREADSHEET_URL);

  var currentRows = fetchNonApprovedAds_();
  var previousMap = loadSnapshot_(ss);

  var currentMap = buildKeyedMap_(currentRows);
  var diff       = computeDiff_(previousMap, currentMap);

  writeAdsSheet_(ss, currentRows);
  writeChangesSheet_(ss, diff);
  writeDashboard_(ss, currentRows, diff);
  saveSnapshot_(ss, currentMap);

  Logger.log('Done. Ads: ' + currentRows.length +
             ', New: ' + diff.added.length +
             ', Changed: ' + diff.changed.length +
             ', Resolved: ' + diff.resolved.length);
}

// ─── DATA FETCH ─────────────────────────────────────────────────────────────

function fetchNonApprovedAds_() {
  var rows = [];
  var report = AdsApp.search(GAQL_NON_APPROVED_ADS);

  while (report.hasNext()) {
    var row = report.next();

    var campaign    = row.campaign;
    var adGroup     = row.adGroup;
    var adGroupAd   = row.adGroupAd;
    var ad          = adGroupAd.ad;
    var policy      = adGroupAd.policySummary;

    var policyTopics   = [];
    var policyTypes    = [];
    var policyEvidence = [];

    if (policy.policyTopicEntries) {
      for (var i = 0; i < policy.policyTopicEntries.length; i++) {
        var entry = policy.policyTopicEntries[i];
        policyTopics.push(entry.topic || '');
        policyTypes.push(entry.type || '');
        policyEvidence.push(extractEvidence_(entry));
      }
    }

    rows.push([
      campaign.name,
      campaign.id,
      adGroup.name,
      adGroup.id,
      ad.id,
      ad.type,
      (ad.finalUrls && ad.finalUrls.length > 0) ? ad.finalUrls[0] : '',
      adGroupAd.status,
      adGroupAd.primaryStatus,
      (adGroupAd.primaryStatusReasons || []).join(', '),
      policy.approvalStatus,
      policy.reviewStatus,
      policyTopics.join(' | '),
      policyTypes.join(' | '),
      policyEvidence.join(' | ')
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
  // campaign_id + ad_group_id + ad_id
  return row[1] + '_' + row[3] + '_' + row[4];
}

function signatureValue_(row) {
  // approval_status + review_status + policy_topics + primary_status
  return row[10] + '|' + row[11] + '|' + row[12] + '|' + row[8];
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
    timestamp,
    changeType,
    currentRow[0],  // Campaign
    currentRow[1],  // Campaign ID
    currentRow[2],  // Ad Group
    currentRow[3],  // Ad Group ID
    currentRow[4],  // Ad ID
    currentRow[10], // Approval Status
    currentRow[8],  // Primary Status
    currentRow[12]  // Policy Topics
  ];

  if (changeType === 'CHANGED' && previousRow) {
    row.push(previousRow[10] + ' → ' + currentRow[10]); // Approval change
    row.push(previousRow[8]  + ' → ' + currentRow[8]);  // Primary status change
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

function writeAdsSheet_(ss, rows) {
  var sheet = getOrCreateSheet_(ss, CONFIG.SHEET_ADS);
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

  var approvalRange = sheet.getRange(2, 11, Math.max(rowCount, 1), 1); // Approval Status col
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
    'Ad Group', 'Ad Group ID', 'Ad ID',
    'Approval Status', 'Primary Status', 'Policy Topics',
    'Approval Change', 'Primary Status Change'
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

  var disapproved    = 0;
  var approvedLimited = 0;
  var areaOfInterest = 0;
  var underReview    = 0;

  for (var i = 0; i < currentRows.length; i++) {
    var approval = currentRows[i][10];
    var review   = currentRows[i][11];
    if (approval === 'DISAPPROVED') disapproved++;
    else if (approval === 'APPROVED_LIMITED') approvedLimited++;
    else if (approval === 'AREA_OF_INTEREST_ONLY') areaOfInterest++;
    if (review === 'REVIEW_IN_PROGRESS' || review === 'UNDER_APPEAL') underReview++;
  }

  var data = [
    ['Ad Disapproval Tracker — Dashboard', ''],
    ['Last Updated', now],
    ['', ''],
    ['CURRENT STATE', ''],
    ['Total Non-Approved Ads', currentRows.length],
    ['Disapproved', disapproved],
    ['Approved (Limited)', approvedLimited],
    ['Area of Interest Only', areaOfInterest],
    ['Under Review / Appeal', underReview],
    ['', ''],
    ['CHANGES THIS RUN', ''],
    ['New Disapprovals', diff.added.length],
    ['Status Changes', diff.changed.length],
    ['Resolved', diff.resolved.length]
  ];

  sheet.getRange(1, 1, data.length, 2).setValues(data);
  sheet.getRange(1, 1).setFontSize(14).setFontWeight('bold');
  sheet.getRange(4, 1).setFontWeight('bold');
  sheet.getRange(11, 1).setFontWeight('bold');

  sheet.getRange(6, 1, 1, 2).setBackground('#f4cccc');
  sheet.getRange(7, 1, 1, 2).setBackground('#fce5cd');
  sheet.getRange(8, 1, 1, 2).setBackground('#fff2cc');
  sheet.getRange(12, 1, 1, 2).setBackground('#f4cccc');
  sheet.getRange(14, 1, 1, 2).setBackground('#d9ead3');
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
