# Ad-Level Fields Reference (Google Ads API v23)

All fields available when querying the `ad_group_ad` resource via GAQL. Sourced directly from the proto definitions in this repository.

---

## 1. AdGroupAd Resource (`ad_group_ad.*`)

| Field | Type | Access | Description |
|---|---|---|---|
| `resource_name` | `string` | Immutable | Resource name. Format: `customers/{customer_id}/adGroupAds/{ad_group_id}~{ad_id}` |
| `status` | `enum` | Read/Write | User-set status of the ad. Values: `ENABLED`, `PAUSED`, `REMOVED` |
| `ad_group` | `string` | Immutable | Resource name of the parent ad group |
| `ad` | `Ad` | Immutable | The ad object (see section 2 below) |
| `start_date_time` | `string` | Read/Write | When the ad starts serving. Format: `yyyy-MM-dd HH:mm:ss`. Only supported for some ad types |
| `end_date_time` | `string` | Read/Write | When the ad stops serving. Format: `yyyy-MM-dd HH:mm:ss`. Only supported for some ad types |
| `policy_summary` | `AdGroupAdPolicySummary` | Output only | Policy findings for this ad (see section 3 below) |
| `ad_strength` | `enum` | Output only | Overall ad strength. Values: `PENDING`, `NO_ADS`, `POOR`, `AVERAGE`, `GOOD`, `EXCELLENT` |
| `action_items` | `repeated string` | Output only | Recommendations to improve ad strength |
| `labels` | `repeated string` | Output only | Resource names of labels attached to this ad |
| `primary_status` | `enum` | Output only | Aggregated serving status (see section 4 below) |
| `primary_status_reasons` | `repeated enum` | Output only | Reasons for the primary status (see section 5 below) |
| `ad_group_ad_asset_automation_settings` | `repeated` | Read/Write | Asset automation opt-in/out per type |

---

## 2. Ad Object (`ad_group_ad.ad.*`)

| Field | Type | Access | Description |
|---|---|---|---|
| `resource_name` | `string` | Immutable | Resource name. Format: `customers/{customer_id}/ads/{ad_id}` |
| `id` | `int64` | Output only | The numeric ad ID |
| `final_urls` | `repeated string` | Read/Write | Final URLs after redirects |
| `final_app_urls` | `repeated FinalAppUrl` | Read/Write | Final app URLs for mobile |
| `final_mobile_urls` | `repeated string` | Read/Write | Final mobile URLs after redirects |
| `tracking_url_template` | `string` | Read/Write | Tracking URL template |
| `final_url_suffix` | `string` | Read/Write | Suffix for constructing final URL |
| `url_custom_parameters` | `repeated CustomParameter` | Read/Write | Custom parameter substitutions for tracking |
| `display_url` | `string` | Read/Write | URL that appears in the ad description |
| `type` | `enum` | Output only | The ad type (see section 6 below) |
| `added_by_google_ads` | `bool` | Output only | Whether Google Ads auto-created this ad |
| `device_preference` | `enum` | Read/Write | Device preference. Values: `MOBILE`, `UNSPECIFIED` |
| `url_collections` | `repeated UrlCollection` | Read/Write | Additional URLs tagged with identifiers |
| `name` | `string` | Immutable | Ad name (for identification only; does not affect serving) |
| `system_managed_resource_source` | `enum` | Output only | Source if system-managed |

### Ad Type-Specific Data (`ad_group_ad.ad.<type>`)

Each ad contains a `oneof ad_data` with type-specific fields. The types are:

| Type Field | Ad Type |
|---|---|
| `text_ad` | Text Ad |
| `expanded_text_ad` | Expanded Text Ad |
| `expanded_dynamic_search_ad` | Expanded Dynamic Search Ad |
| `hotel_ad` | Hotel Ad |
| `shopping_smart_ad` | Smart Shopping Ad |
| `shopping_product_ad` | Shopping Product Ad |
| `image_ad` | Image Ad |
| `video_ad` | Video Ad |
| `video_responsive_ad` | Video Responsive Ad |
| `responsive_search_ad` | Responsive Search Ad |
| `legacy_responsive_display_ad` | Legacy Responsive Display Ad |
| `app_ad` | App Ad |
| `legacy_app_install_ad` | Legacy App Install Ad |
| `responsive_display_ad` | Responsive Display Ad |
| `local_ad` | Local Ad |
| `display_upload_ad` | Display Upload Ad |
| `app_engagement_ad` | App Engagement Ad |
| `shopping_comparison_listing_ad` | Shopping Comparison Listing Ad |
| `smart_campaign_ad` | Smart Campaign Ad |
| `app_pre_registration_ad` | App Pre-Registration Ad |
| `demand_gen_multi_asset_ad` | Demand Gen Multi Asset Ad |
| `demand_gen_carousel_ad` | Demand Gen Carousel Ad |
| `demand_gen_video_responsive_ad` | Demand Gen Video Responsive Ad |
| `demand_gen_product_ad` | Demand Gen Product Ad |
| `travel_ad` | Travel Ad |

---

## 3. Policy Summary (`ad_group_ad.policy_summary.*`)

| Field | Type | Access | Description |
|---|---|---|---|
| `policy_topic_entries` | `repeated PolicyTopicEntry` | Output only | List of policy findings for this ad |
| `review_status` | `enum` | Output only | Where in the review process this ad is (see section 7) |
| `approval_status` | `enum` | Output only | Overall approval status (see section 8) |

### PolicyTopicEntry (`ad_group_ad.policy_summary.policy_topic_entries[]`)

| Field | Type | Description |
|---|---|---|
| `topic` | `string` | Policy topic name (e.g. `ALCOHOL`, `TRADEMARKS_IN_AD_TEXT`, `DESTINATION_NOT_WORKING`) |
| `type` | `enum` | Effect on serving (see section 9) |
| `evidences` | `repeated PolicyTopicEvidence` | Evidence for the finding |
| `constraints` | `repeated PolicyTopicConstraint` | How serving may be restricted |

### PolicyTopicEvidence (`ad_group_ad.policy_summary.policy_topic_entries[].evidences[]`)

| Evidence Type | Description |
|---|---|
| `website_list` | Websites that caused the finding |
| `text_list` | Text fragments that violated the policy |
| `language_code` | Detected language (IETF tag, e.g. `en-US`) |
| `destination_text_list` | Text found on the destination page |
| `destination_mismatch` | URL mismatch types |
| `destination_not_working` | Details: `expanded_url`, `device`, `last_checked_date_time`, `dns_error_type` or `http_error_code` |

### PolicyTopicConstraint (`ad_group_ad.policy_summary.policy_topic_entries[].constraints[]`)

| Constraint Type | Description |
|---|---|
| `country_constraint_list` | Countries where the resource cannot serve. Contains `total_targeted_countries` and list of `country_criterion` geo targets |
| `reseller_constraint` | Disapproved for reseller purposes |
| `certificate_missing_in_country_list` | Countries where a certificate is required |
| `certificate_domain_mismatch_in_country_list` | Countries where certificate domain doesn't match |

---

## 4. AdGroupAd Primary Status (`ad_group_ad.primary_status`)

Aggregated view of why an ad is or isn't serving.

| Value | Meaning |
|---|---|
| `ELIGIBLE` | Ad is eligible to serve |
| `PAUSED` | Ad is paused |
| `REMOVED` | Ad is removed |
| `PENDING` | Cannot serve now but may serve later without advertiser action |
| `LIMITED` | Serving in a limited capacity |
| `NOT_ELIGIBLE` | Not eligible to serve |

---

## 5. AdGroupAd Primary Status Reasons (`ad_group_ad.primary_status_reasons`)

Granular reasons that drive the primary status.

| Value | Contributes To | Description |
|---|---|---|
| `CAMPAIGN_REMOVED` | REMOVED | Campaign status is removed |
| `CAMPAIGN_PAUSED` | PAUSED | Campaign status is paused |
| `CAMPAIGN_PENDING` | PENDING | Campaign start date is in the future |
| `CAMPAIGN_ENDED` | ENDED | Campaign end date has passed |
| `AD_GROUP_PAUSED` | PAUSED | Ad group is paused |
| `AD_GROUP_REMOVED` | REMOVED | Ad group is removed |
| `AD_GROUP_AD_PAUSED` | PAUSED | Ad itself is paused |
| `AD_GROUP_AD_REMOVED` | REMOVED | Ad itself is removed |
| `AD_GROUP_AD_DISAPPROVED` | NOT_ELIGIBLE | **Ad is disapproved by policy** |
| `AD_GROUP_AD_UNDER_REVIEW` | PENDING | Ad is under review |
| `AD_GROUP_AD_POOR_QUALITY` | LIMITED | Ad is flagged as poor quality |
| `AD_GROUP_AD_NO_ADS` | PENDING | No eligible ad instances could be generated |
| `AD_GROUP_AD_APPROVED_LABELED` | LIMITED | Internally labeled with a limiting label |
| `AD_GROUP_AD_AREA_OF_INTEREST_ONLY` | LIMITED | Only serving in area of interest |
| `AD_GROUP_AD_UNDER_APPEAL` | *(no impact)* | Part of an ongoing appeal |

---

## 6. Ad Type (`ad_group_ad.ad.type`)

| Value | Description |
|---|---|
| `TEXT_AD` | Text ad |
| `EXPANDED_TEXT_AD` | Expanded text ad |
| `EXPANDED_DYNAMIC_SEARCH_AD` | Expanded dynamic search ad |
| `HOTEL_AD` | Hotel ad |
| `SHOPPING_SMART_AD` | Smart Shopping ad |
| `SHOPPING_PRODUCT_AD` | Standard Shopping ad |
| `VIDEO_AD` | Video ad |
| `IMAGE_AD` | Image ad |
| `RESPONSIVE_SEARCH_AD` | Responsive search ad |
| `LEGACY_RESPONSIVE_DISPLAY_AD` | Legacy responsive display ad |
| `APP_AD` | App ad |
| `LEGACY_APP_INSTALL_AD` | Legacy app install ad |
| `RESPONSIVE_DISPLAY_AD` | Responsive display ad |
| `LOCAL_AD` | Local ad |
| `HTML5_UPLOAD_AD` | HTML5 upload display ad |
| `DYNAMIC_HTML5_AD` | Dynamic HTML5 display ad |
| `APP_ENGAGEMENT_AD` | App engagement ad |
| `SHOPPING_COMPARISON_LISTING_AD` | Shopping comparison listing ad |
| `VIDEO_BUMPER_AD` | Video bumper ad |
| `VIDEO_NON_SKIPPABLE_IN_STREAM_AD` | Video non-skippable in-stream ad |
| `VIDEO_TRUEVIEW_IN_STREAM_AD` | Video TrueView in-stream ad |
| `VIDEO_RESPONSIVE_AD` | Video responsive ad |
| `SMART_CAMPAIGN_AD` | Smart campaign ad |
| `CALL_AD` | Call ad |
| `APP_PRE_REGISTRATION_AD` | App pre-registration ad |
| `IN_FEED_VIDEO_AD` | In-feed video ad |
| `DEMAND_GEN_MULTI_ASSET_AD` | Demand Gen multi asset ad |
| `DEMAND_GEN_CAROUSEL_AD` | Demand Gen carousel ad |
| `TRAVEL_AD` | Travel ad |
| `DEMAND_GEN_VIDEO_RESPONSIVE_AD` | Demand Gen video responsive ad |
| `DEMAND_GEN_PRODUCT_AD` | Demand Gen product ad |
| `YOUTUBE_AUDIO_AD` | YouTube audio ad |

---

## 7. Policy Review Status (`ad_group_ad.policy_summary.review_status`)

| Value | Description |
|---|---|
| `REVIEW_IN_PROGRESS` | Currently under review |
| `REVIEWED` | Primary review complete (other reviews may continue) |
| `UNDER_APPEAL` | Resubmitted for approval or decision has been appealed |
| `ELIGIBLE_MAY_SERVE` | Eligible and may be serving, but could still undergo further review |

---

## 8. Policy Approval Status (`ad_group_ad.policy_summary.approval_status`)

Severity order (most to least severe): DISAPPROVED > AREA_OF_INTEREST_ONLY > APPROVED_LIMITED > APPROVED

| Value | Description |
|---|---|
| `DISAPPROVED` | Will not serve |
| `APPROVED_LIMITED` | Serves with restrictions |
| `APPROVED` | Serves without restrictions |
| `AREA_OF_INTEREST_ONLY` | Will not serve in targeted countries, but may serve for users searching for info about those countries |

---

## 9. Policy Topic Entry Type (`ad_group_ad.policy_summary.policy_topic_entries[].type`)

| Value | Description |
|---|---|
| `PROHIBITED` | The resource will not be served |
| `LIMITED` | The resource will not be served under some circumstances |
| `FULLY_LIMITED` | Cannot serve at all because of current targeting criteria |
| `DESCRIPTIVE` | May be of interest but does not limit serving |
| `BROADENING` | Could increase coverage beyond normal |
| `AREA_OF_INTEREST_ONLY` | Constrained for all targeted countries, may serve in others through area of interest |

---

## 10. Parent-Level Fields Available via GAQL Joins

When querying `ad_group_ad`, you can also select fields from parent resources:

### Campaign (`campaign.*`)

| Field | Description |
|---|---|
| `campaign.id` | Campaign ID |
| `campaign.name` | Campaign name |
| `campaign.status` | Campaign status: `ENABLED`, `PAUSED`, `REMOVED` |
| `campaign.advertising_channel_type` | Channel type: `SEARCH`, `DISPLAY`, `SHOPPING`, `HOTEL`, `VIDEO`, `MULTI_CHANNEL`, `LOCAL`, `SMART`, `PERFORMANCE_MAX`, `LOCAL_SERVICES`, `TRAVEL`, `DEMAND_GEN` |
| `campaign.resource_name` | Campaign resource name |

### Ad Group (`ad_group.*`)

| Field | Description |
|---|---|
| `ad_group.id` | Ad group ID |
| `ad_group.name` | Ad group name |
| `ad_group.status` | Ad group status: `ENABLED`, `PAUSED`, `REMOVED` |
| `ad_group.type` | Ad group type |
| `ad_group.resource_name` | Ad group resource name |

### Customer (`customer.*`)

| Field | Description |
|---|---|
| `customer.id` | Account ID |
| `customer.descriptive_name` | Account name |
| `customer.resource_name` | Customer resource name |

---

## 11. Metrics Available (select via `metrics.*`)

Common metrics that can be joined when querying `ad_group_ad`:

| Field | Description |
|---|---|
| `metrics.impressions` | Total impressions |
| `metrics.clicks` | Total clicks |
| `metrics.cost_micros` | Total cost in micros |
| `metrics.conversions` | Total conversions |
| `metrics.ctr` | Click-through rate |
| `metrics.average_cpc` | Average CPC |
| `metrics.average_cpm` | Average CPM |
| `metrics.conversions_value` | Total conversion value |

*Note: Metrics require a date range in the WHERE clause or via `segments.date`.*

---

*Source: Proto definitions from `google/ads/googleads/v23/` in this repository.*
