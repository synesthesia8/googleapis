# Backlog

Open issues and improvements to revisit. Newest first.

---

### BL-001: Tracker only watches approval status — missing entity state changes

**Date logged:** 2026-04-03
**Status:** Open
**Related tables:** `ads_v2.policy_timeline`, all source tables

**The problem:** The `policy_timeline` table only tracks `approvalStatus` changes. When an ad gets removed (`adGroupAd.status: ENABLED → REMOVED`), the approval status often goes to null — but we don't log the status change that caused it. This makes it look like the disapproval just vanished with no explanation.

Same issue applies to:
- Ad status (ENABLED/PAUSED/REMOVED)
- Campaign status (ENABLED/PAUSED/REMOVED)
- Campaign serving status (SERVING/NONE)
- Ad group status (ENABLED/PAUSED/REMOVED)
- Asset enabled flag in ad (true/false)
- Campaign/ad group asset link status and primaryStatus

**Why it matters:** Without tracking these, you can't correlate operational changes with policy changes. "Why did this disapproval disappear?" has no answer without knowing the ad was removed.

**Context:** Full field mapping and architecture discussion in this conversation. See `docs/sources/google-ads-approval-change-scenarios.md` for the five scenarios documented.
