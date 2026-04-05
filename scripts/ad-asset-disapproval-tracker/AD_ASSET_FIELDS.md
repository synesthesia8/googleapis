# Ad Asset Fields Reference (Google Ads API v23)

All fields available when querying the `ad_group_ad_asset_view` resource via GAQL.
Sourced directly from the proto definitions in this repository.

This resource represents the **link between an ad and an asset** — it tells you
which asset is playing which role inside which ad, and what Google's policy
verdict is for that asset in that specific context.

---

## Important: Supported Ad Types

`ad_group_ad_asset_view` only supports the following ad types:

- **Responsive Search Ads (RSA)**
- **App Ads**
- **Demand Gen campaigns**

It does **NOT** support Responsive Display Ads. For those, asset-level policy
data must come from the standalone asset link resources (`customer_asset`,
`campaign_asset`, `ad_group_asset`).

---

## 1. AdGroupAdAssetView Resource (`ad_group_ad_asset_view.*`)

| Field | Type | Access | Description |
|---|---|---|---|
| `resource_name` | `string` | Output only | Resource name. Format: `customers/{customer_id}/adGroupAdAssetViews/{ad_group_id}~{ad_id}~{asset_id}~{field_type}` |
| `ad_group_ad` | `string` | Output only | Resource name of the parent AdGroupAd. Links this asset back to its ad |
| `asset` | `string` | Output only | Resource name of the asset. Format: `customers/{customer_id}/assets/{asset_id}` |
| `field_type` | `enum` | Output only | The role this asset plays inside the ad (see section 4 below) |
| `enabled` | `bool` | Output only | Whether this asset is linked to the **latest version** of the ad. `false` means the link existed but has been removed |
| `policy_summary` | `AdGroupAdAssetPolicySummary` | Output only | Policy findings for this asset in the context of this ad (see section 2 below) |
| `performance_label` | `enum` | Output only | Performance rating of this asset linkage (see section 5 below) |
| `pinned_field` | `enum` | Output only | If the asset is pinned to a specific position, this indicates where (see section 6 below) |
| `source` | `enum` | Output only | Who created this asset link (see section 7 below) |

---

## 2. Policy Summary (`ad_group_ad_asset_view.policy_summary.*`)

This is the critical structure for disapproval tracking. It tells you exactly
what's wrong with this specific asset inside this specific ad.

| Field | Type | Access | Description |
|---|---|---|---|
| `policy_topic_entries` | `repeated PolicyTopicEntry` | Output only | List of policy findings for this asset-in-ad |
| `review_status` | `enum` | Output only | Where in the review process this asset is (see section 8) |
| `approval_status` | `enum` | Output only | Overall approval status for this asset-in-ad (see section 9) |

### PolicyTopicEntry (`ad_group_ad_asset_view.policy_summary.policy_topic_entries[]`)

Each entry represents a single policy finding — one specific reason this asset
has a problem.

| Field | Type | Description |
|---|---|---|
| `topic` | `string` | The policy topic name. Examples: `ALCOHOL`, `TRADEMARKS_IN_AD_TEXT`, `DESTINATION_NOT_WORKING`, `HEALTHCARE_AND_MEDICINES`, `GAMBLING_AND_GAMES`, `COPYRIGHTED_CONTENT`, `MISLEADING_CONTENT`, `ADULT_CONTENT`. The set of possible topics is not fixed and may change at any time |
| `type` | `enum` | The effect this finding has on serving (see section 10) |
| `evidences` | `repeated PolicyTopicEvidence` | Evidence supporting this finding (see section 11) |
| `constraints` | `repeated PolicyTopicConstraint` | How serving is restricted (see section 12) |

---

## 3. Asset Resource (`asset.*`)

When querying `ad_group_ad_asset_view`, you can join the `asset` resource to get
details about the asset itself (not just its policy status in the ad context).

| Field | Type | Access | Description |
|---|---|---|---|
| `resource_name` | `string` | Immutable | Format: `customers/{customer_id}/assets/{asset_id}` |
| `id` | `int64` | Output only | The numeric asset ID |
| `name` | `string` | Optional | Human-readable name (for identification only) |
| `type` | `enum` | Output only | The asset's content type (see section 13) |
| `final_urls` | `repeated string` | Read/Write | Final URLs after redirects (for sitelink-type assets) |
| `final_mobile_urls` | `repeated string` | Read/Write | Final mobile URLs |
| `tracking_url_template` | `string` | Read/Write | Tracking URL template |
| `final_url_suffix` | `string` | Read/Write | Suffix for constructing final URL |
| `url_custom_parameters` | `repeated CustomParameter` | Read/Write | Custom param substitutions |
| `source` | `enum` | Output only | Who created this asset: `ADVERTISER` or `AUTOMATICALLY_CREATED` |
| `policy_summary` | `AssetPolicySummary` | Output only | Global policy summary for this asset (independent of any ad context) |
| `field_type_policy_summaries` | `repeated AssetFieldTypePolicySummary` | Output only | Policy summaries broken down by field type |
| `orientation` | `enum` | Output only | Orientation for image/video assets |

### Asset Policy Summary (`asset.policy_summary.*`)

This is the **global** policy status for the asset itself, independent of which
ad it appears in. Compare with `ad_group_ad_asset_view.policy_summary` which is
the policy status **in the context of a specific ad**.

| Field | Type | Access | Description |
|---|---|---|---|
| `policy_topic_entries` | `repeated PolicyTopicEntry` | Output only | Global policy findings |
| `review_status` | `enum` | Output only | Global review status |
| `approval_status` | `enum` | Output only | Global approval status |

### Asset Field Type Policy Summary (`asset.field_type_policy_summaries[]`)

Policy summary broken down by field type. The same asset can have different
policy outcomes depending on whether it's used as a HEADLINE vs. a DESCRIPTION.

| Field | Type | Access | Description |
|---|---|---|---|
| `asset_field_type` | `enum` | Output only | The field type this summary applies to |
| `asset_source` | `enum` | Output only | Source of the asset |
| `policy_summary_info` | `AssetPolicySummary` | Output only | Policy summary for this specific field type usage |

### Asset-Type-Specific Data (`asset.<type>`)

Each asset has a `oneof asset_data` containing type-specific content:

| Type Field | Asset Type | Content |
|---|---|---|
| `youtube_video_asset` | YouTube Video | Video ID, title |
| `media_bundle_asset` | Media Bundle | Zipped HTML5 bundle |
| `image_asset` | Image | Image data, dimensions, MIME type |
| `text_asset` | Text | The actual text string |
| `lead_form_asset` | Lead Form | Form configuration |
| `book_on_google_asset` | Book on Google | Booking config |
| `promotion_asset` | Promotion | Promo details, discount, dates |
| `callout_asset` | Callout | Callout text |
| `structured_snippet_asset` | Structured Snippet | Header + values |
| `sitelink_asset` | Sitelink | Link text, description lines, URL |
| `page_feed_asset` | Page Feed | Page URLs |
| `dynamic_education_asset` | Dynamic Education | School/program details |
| `mobile_app_asset` | Mobile App | App store, app ID |
| `hotel_callout_asset` | Hotel Callout | Hotel-specific callout text |
| `call_asset` | Call | Phone number, conversion config |
| `price_asset` | Price | Price offerings |
| `call_to_action_asset` | Call to Action | CTA type |
| `dynamic_real_estate_asset` | Dynamic Real Estate | Property details |
| `dynamic_custom_asset` | Dynamic Custom | Custom key-value pairs |
| `dynamic_hotels_and_rentals_asset` | Dynamic Hotels & Rentals | Hotel/rental details |
| `dynamic_flights_asset` | Dynamic Flights | Flight details |
| `demand_gen_carousel_card_asset` | Demand Gen Carousel Card | Card headline, image, CTA |
| `dynamic_travel_asset` | Dynamic Travel | Travel details |
| `dynamic_local_asset` | Dynamic Local | Local business details |
| `dynamic_jobs_asset` | Dynamic Jobs | Job listing details |
| `location_asset` | Location | Business location |
| `hotel_property_asset` | Hotel Property | Hotel property ID, name |
| `business_message_asset` | Business Message | Messaging config |
| `app_deep_link_asset` | App Deep Link | Deep link config |
| `youtube_video_list_asset` | YouTube Video List | List of video IDs |

---

## 4. Asset Field Type (`ad_group_ad_asset_view.field_type`)

The role this asset plays inside the ad. This is **the most important enum for
understanding what you're looking at** — it tells you which slot in the ad the
disapproved asset occupies.

| Value | Description |
|---|---|
| `HEADLINE` | Linked as a headline |
| `DESCRIPTION` | Linked as a description |
| `LONG_HEADLINE` | Linked as a long headline (Demand Gen / multi-asset) |
| `LONG_DESCRIPTION` | Linked as a long description |
| `MANDATORY_AD_TEXT` | Linked as mandatory ad text |
| `MARKETING_IMAGE` | Linked as a marketing image (landscape) |
| `SQUARE_MARKETING_IMAGE` | Linked as a square marketing image |
| `PORTRAIT_MARKETING_IMAGE` | Linked as a portrait marketing image |
| `TALL_PORTRAIT_MARKETING_IMAGE` | Linked as a tall portrait marketing image |
| `LOGO` | Linked as a logo |
| `LANDSCAPE_LOGO` | Linked as a landscape logo |
| `BUSINESS_LOGO` | Linked as a business logo |
| `BUSINESS_NAME` | Linked as a business name |
| `YOUTUBE_VIDEO` | Linked as a YouTube video |
| `VIDEO` | Linked as a non-YouTube video |
| `MEDIA_BUNDLE` | Linked as a media bundle |
| `SITELINK` | Linked as a sitelink extension |
| `CALLOUT` | Linked as a callout extension |
| `STRUCTURED_SNIPPET` | Linked as a structured snippet extension |
| `CALL` | Linked as a call extension |
| `PRICE` | Linked as a price extension |
| `PROMOTION` | Linked as a promotion extension |
| `LEAD_FORM` | Linked as a lead form extension |
| `MOBILE_APP` | Linked as a mobile app extension |
| `HOTEL_CALLOUT` | Linked as a hotel callout extension |
| `BOOK_ON_GOOGLE` | Linked to indicate "Book on Google" |
| `AD_IMAGE` | Linked as an ad image |
| `CALL_TO_ACTION_SELECTION` | Linked to select a CTA |
| `CALL_TO_ACTION` | Linked as a call-to-action |
| `HOTEL_PROPERTY` | Linked as a hotel property (PMax for travel) |
| `DEMAND_GEN_CAROUSEL_CARD` | Linked as a Demand Gen carousel card |
| `BUSINESS_MESSAGE` | Linked as a business message |
| `RELATED_YOUTUBE_VIDEOS` | Linked as related YouTube videos |
| `LANDING_PAGE_PREVIEW` | Linked as a landing page preview image |

---

## 5. Asset Performance Label (`ad_group_ad_asset_view.performance_label`)

How well this asset is performing within the ad.

| Value | Description |
|---|---|
| `PENDING` | No performance data yet (may be under review) |
| `LEARNING` | Getting impressions but not statistically significant yet |
| `LOW` | Worst performing asset |
| `GOOD` | Good performing asset |
| `BEST` | Best performing asset |
| `NOT_APPLICABLE` | Cannot assign performance label (not used by asset-based creatives) |

---

## 6. Pinned Field (`ad_group_ad_asset_view.pinned_field`)

If the asset is pinned to a specific position in the ad, this tells you where.

| Value | Description |
|---|---|
| `HEADLINE_1` | Pinned to headline position 1 |
| `HEADLINE_2` | Pinned to headline position 2 |
| `HEADLINE_3` | Pinned to headline position 3 |
| `DESCRIPTION_1` | Pinned to description position 1 |
| `DESCRIPTION_2` | Pinned to description position 2 |
| `HEADLINE` | Pinned to headline (single-headline ads) |
| `HEADLINE_IN_PORTRAIT` | Headline in portrait image |
| `LONG_HEADLINE` | Pinned as long headline |
| `DESCRIPTION` | Pinned to description (single-description ads) |
| `DESCRIPTION_IN_PORTRAIT` | Description in portrait image |
| `BUSINESS_NAME_IN_PORTRAIT` | Business name in portrait image |
| `BUSINESS_NAME` | Pinned as business name |
| `MARKETING_IMAGE` | Pinned as marketing image |
| `MARKETING_IMAGE_IN_PORTRAIT` | Marketing image in portrait image |
| `SQUARE_MARKETING_IMAGE` | Pinned as square marketing image |
| `PORTRAIT_MARKETING_IMAGE` | Pinned as portrait marketing image |
| `LOGO` | Pinned as logo |
| `LANDSCAPE_LOGO` | Pinned as landscape logo |
| `CALL_TO_ACTION` | Pinned as CTA |
| `YOU_TUBE_VIDEO` | Pinned as YouTube video |
| `SITELINK` | Pinned as sitelink |
| `CALL` | Pinned as call |
| `MOBILE_APP` | Pinned as mobile app |
| `CALLOUT` | Pinned as callout |
| `STRUCTURED_SNIPPET` | Pinned as structured snippet |
| `PRICE` | Pinned as price |
| `PROMOTION` | Pinned as promotion |
| `AD_IMAGE` | Pinned as ad image |
| `LEAD_FORM` | Pinned as lead form |
| `BUSINESS_LOGO` | Pinned as business logo |

---

## 7. Asset Source (`ad_group_ad_asset_view.source`)

Who created this asset link.

| Value | Description |
|---|---|
| `ADVERTISER` | Created by the advertiser |
| `AUTOMATICALLY_CREATED` | Generated by Google automatically |

---

## 8. Policy Review Status (`ad_group_ad_asset_view.policy_summary.review_status`)

Where in the review process this asset-in-ad is.

| Value | Description |
|---|---|
| `REVIEW_IN_PROGRESS` | Currently under review |
| `REVIEWED` | Primary review complete (other reviews may continue) |
| `UNDER_APPEAL` | Resubmitted for approval or decision has been appealed |
| `ELIGIBLE_MAY_SERVE` | Eligible and may be serving, but could still undergo further review |

---

## 9. Policy Approval Status (`ad_group_ad_asset_view.policy_summary.approval_status`)

Severity order (most to least): DISAPPROVED > AREA_OF_INTEREST_ONLY > APPROVED_LIMITED > APPROVED

| Value | Description |
|---|---|
| `DISAPPROVED` | Will not serve |
| `APPROVED_LIMITED` | Serves with restrictions |
| `APPROVED` | Serves without restrictions |
| `AREA_OF_INTEREST_ONLY` | Won't serve in targeted countries, may serve for users searching for info about those countries |

---

## 10. Policy Topic Entry Type (`ad_group_ad_asset_view.policy_summary.policy_topic_entries[].type`)

The effect this finding has on serving.

| Value | Description |
|---|---|
| `PROHIBITED` | The asset will not be served |
| `LIMITED` | The asset will not be served under some circumstances |
| `FULLY_LIMITED` | Cannot serve at all due to current targeting criteria |
| `DESCRIPTIVE` | May be of interest but does not limit serving |
| `BROADENING` | Could increase coverage beyond normal |
| `AREA_OF_INTEREST_ONLY` | Constrained for targeted countries, may serve in others via area of interest |

---

## 11. Policy Topic Evidence (`ad_group_ad_asset_view.policy_summary.policy_topic_entries[].evidences[]`)

Evidence supporting a policy finding. Each evidence has a `oneof value`:

| Evidence Type | Fields | Description |
|---|---|---|
| `text_list` | `texts: repeated string` | Text fragments that violated the policy |
| `website_list` | `websites: repeated string` | Websites that caused the finding |
| `language_code` | `string` (IETF tag) | The language the resource was detected to be written in |
| `destination_text_list` | `destination_texts: repeated string` | Text found on the destination page |
| `destination_mismatch` | `url_types: repeated enum` | Mismatch between resource URLs |
| `destination_not_working` | `expanded_url`, `device`, `last_checked_date_time`, `dns_error_type` or `http_error_code` | Destination returning errors or not functional |

---

## 12. Policy Topic Constraints (`ad_group_ad_asset_view.policy_summary.policy_topic_entries[].constraints[]`)

How serving may be restricted. Each constraint has a `oneof value`:

| Constraint Type | Description |
|---|---|
| `country_constraint_list` | Countries where the resource cannot serve. Contains `total_targeted_countries` and list of `country_criterion` geo targets |
| `reseller_constraint` | Disapproved for reseller purposes |
| `certificate_missing_in_country_list` | Countries where a certificate is required for serving |
| `certificate_domain_mismatch_in_country_list` | Countries where the certificate domain doesn't match |

---

## 13. Asset Type (`asset.type`)

The content type of the asset itself.

| Value | Description |
|---|---|
| `YOUTUBE_VIDEO` | YouTube video |
| `MEDIA_BUNDLE` | Media bundle (HTML5) |
| `IMAGE` | Image |
| `TEXT` | Text |
| `LEAD_FORM` | Lead form |
| `BOOK_ON_GOOGLE` | Book on Google |
| `PROMOTION` | Promotion |
| `CALLOUT` | Callout |
| `STRUCTURED_SNIPPET` | Structured snippet |
| `SITELINK` | Sitelink |
| `PAGE_FEED` | Page feed |
| `DYNAMIC_EDUCATION` | Dynamic education |
| `MOBILE_APP` | Mobile app |
| `HOTEL_CALLOUT` | Hotel callout |
| `CALL` | Call |
| `PRICE` | Price |
| `CALL_TO_ACTION` | Call to action |
| `DYNAMIC_REAL_ESTATE` | Dynamic real estate |
| `DYNAMIC_CUSTOM` | Dynamic custom |
| `DYNAMIC_HOTELS_AND_RENTALS` | Dynamic hotels and rentals |
| `DYNAMIC_FLIGHTS` | Dynamic flights |
| `DYNAMIC_TRAVEL` | Dynamic travel |
| `DYNAMIC_LOCAL` | Dynamic local |
| `DYNAMIC_JOBS` | Dynamic jobs |
| `LOCATION` | Location |
| `HOTEL_PROPERTY` | Hotel property |
| `DEMAND_GEN_CAROUSEL_CARD` | Demand Gen carousel card |
| `BUSINESS_MESSAGE` | Business message |
| `APP_DEEP_LINK` | App deep link |
| `YOUTUBE_VIDEO_LIST` | YouTube video list |

---

## 14. Parent-Level Fields Available via GAQL Joins

When querying `ad_group_ad_asset_view`, you can select fields from parent resources
to build the full drill-down chain:

### Campaign (`campaign.*`)

| Field | Description |
|---|---|
| `campaign.id` | Campaign ID |
| `campaign.name` | Campaign name |
| `campaign.status` | Campaign status: `ENABLED`, `PAUSED`, `REMOVED` |
| `campaign.advertising_channel_type` | Channel type: `SEARCH`, `DISPLAY`, `SHOPPING`, `HOTEL`, `VIDEO`, `MULTI_CHANNEL`, `LOCAL`, `SMART`, `PERFORMANCE_MAX`, `LOCAL_SERVICES`, `TRAVEL`, `DEMAND_GEN` |

### Ad Group (`ad_group.*`)

| Field | Description |
|---|---|
| `ad_group.id` | Ad group ID |
| `ad_group.name` | Ad group name |
| `ad_group.status` | Ad group status: `ENABLED`, `PAUSED`, `REMOVED` |

### Ad Group Ad (`ad_group_ad.*`)

| Field | Description |
|---|---|
| `ad_group_ad.ad.id` | Ad ID |
| `ad_group_ad.ad.type` | Ad type (RSA, App Ad, Demand Gen, etc.) |
| `ad_group_ad.status` | User-set ad status: `ENABLED`, `PAUSED`, `REMOVED` |
| `ad_group_ad.primary_status` | Aggregated serving status |
| `ad_group_ad.primary_status_reasons` | Reasons for primary status |
| `ad_group_ad.policy_summary.approval_status` | Overall ad-level approval status |

### Customer (`customer.*`)

| Field | Description |
|---|---|
| `customer.id` | Account ID |
| `customer.descriptive_name` | Account name |

---

## 15. Key Relationships

```
customer (account)
  └── campaign
       └── ad_group
            └── ad_group_ad (the ad)
                 ├── policy_summary         → ad-level policy verdict
                 └── ad_group_ad_asset_view (one per asset-in-ad)
                      ├── field_type        → HEADLINE, DESCRIPTION, IMAGE, etc.
                      ├── policy_summary    → asset-level policy verdict IN THIS AD
                      └── asset
                           ├── type         → TEXT, IMAGE, VIDEO, etc.
                           └── policy_summary → asset-level policy verdict GLOBALLY
```

An ad can be `DISAPPROVED` at the ad level (`ad_group_ad.policy_summary`) because
one or more of its assets are `DISAPPROVED` at the asset-in-ad level
(`ad_group_ad_asset_view.policy_summary`). The asset itself may be `APPROVED`
globally (`asset.policy_summary`) but `DISAPPROVED` in the context of a specific
ad. This is why both levels matter.

---

*Source: Proto definitions from `google/ads/googleads/v23/` in this repository.*
