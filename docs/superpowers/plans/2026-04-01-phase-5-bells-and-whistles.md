# Phase 5: Alerts, Incidents, Flap Detection & Monitoring

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the PagerDuty-style alert/incident system, flap detection, freshness tracking, pipeline health monitoring, and Supabase Realtime notifications. This transforms the system from "a dashboard you check" to "a system that taps you on the shoulder."

**Architecture:** Alerts fire per-entity (asset_link or ad) when approval_status goes non-approved. Incidents group alerts by root cause asset. Flap detection suppresses noise. Realtime pushes notifications. Pipeline health view monitors the monitoring system.

**Tech Stack:** PL/pgSQL triggers, Supabase Realtime, pg_cron

**Depends on:** Phase 4 (full system working end-to-end with real data)

**Spec reference:** `docs/superpowers/specs/2026-04-01-google-ads-asset-policy-monitor-design.md` — Incident Management, Flap Detection, Pipeline Health, Supabase Realtime sections

---

### Task 1: Create alert and incident tables

**Files:**
- Create: `supabase/migrations/00015_create_alerts_incidents.sql`
- Create: `supabase/tests/00010_alerts_incidents.sql`

- [ ] **Step 1: Write the test**

```sql
-- supabase/tests/00010_alerts_incidents.sql
BEGIN;
SELECT plan(4);

SELECT has_table('ads', 'policy_alerts', 'policy_alerts table should exist');
SELECT has_table('ads', 'policy_incidents', 'policy_incidents table should exist');
SELECT has_index('ads', 'policy_incidents', 'idx_incidents_asset_open', 'unique open incident per asset index should exist');
SELECT has_index('ads', 'policy_alerts', 'idx_alerts_entity', 'alerts entity index should exist');

SELECT * FROM finish();
ROLLBACK;
```

- [ ] **Step 2: Write the migration**

```sql
-- supabase/migrations/00015_create_alerts_incidents.sql

CREATE TABLE ads.policy_incidents (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  customer_id         text NOT NULL,
  asset_id            bigint NOT NULL,
  alert_count         int NOT NULL DEFAULT 0,
  firing_count        int NOT NULL DEFAULT 0,
  opened_at           timestamptz NOT NULL DEFAULT now(),
  resolved_at         timestamptz,
  resolution_duration interval GENERATED ALWAYS AS (resolved_at - opened_at) STORED,
  status              text NOT NULL DEFAULT 'OPEN',

  CONSTRAINT valid_incident_status CHECK (status IN ('OPEN', 'RESOLVED'))
);

CREATE UNIQUE INDEX idx_incidents_asset_open
  ON ads.policy_incidents (customer_id, asset_id)
  WHERE status = 'OPEN';

CREATE INDEX idx_incidents_open
  ON ads.policy_incidents (customer_id, status)
  WHERE status = 'OPEN';

CREATE TABLE ads.policy_alerts (
  id                bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  customer_id       text NOT NULL,
  incident_id       uuid REFERENCES ads.policy_incidents(id),
  entity_type       text NOT NULL,
  entity_id         bigint NOT NULL,
  asset_id          bigint NOT NULL,
  approval_status   text NOT NULL,
  previous_status   text,
  policy_topic_names text[],
  fired_at          timestamptz NOT NULL DEFAULT now(),
  resolved_at       timestamptz,
  status            text NOT NULL DEFAULT 'FIRING',

  CONSTRAINT valid_alert_status CHECK (status IN ('FIRING', 'RESOLVED'))
);

CREATE INDEX idx_alerts_incident
  ON ads.policy_alerts (incident_id, status)
  WHERE status = 'FIRING';

CREATE INDEX idx_alerts_entity
  ON ads.policy_alerts (entity_type, entity_id, status)
  WHERE status = 'FIRING';
```

- [ ] **Step 3: Apply and run tests**

```bash
supabase db reset && supabase test db
```

- [ ] **Step 4: Commit**

```bash
git add supabase/migrations/ supabase/tests/
git commit -m "feat: create policy_alerts and policy_incidents tables"
```

---

### Task 2: Create incident management trigger

**Files:**
- Create: `supabase/migrations/00016_create_incident_trigger.sql`
- Create: `supabase/tests/00011_incident_lifecycle.sql`

- [ ] **Step 1: Write the test**

```sql
-- supabase/tests/00011_incident_lifecycle.sql
BEGIN;
SELECT plan(8);

-- Seed
INSERT INTO ads.accounts (customer_id) VALUES ('test-cid');
INSERT INTO ads.campaigns (campaign_id, customer_id, name, status, serving_status) VALUES (1, 'test-cid', 'C1', 'ENABLED', 'SERVING');
INSERT INTO ads.ad_groups (ad_group_id, customer_id, campaign_id, name, status) VALUES (1, 'test-cid', 1, 'AG1', 'ENABLED');
INSERT INTO ads.ads (ad_id, customer_id, ad_group_id, status, approval_status) VALUES (1, 'test-cid', 1, 'ENABLED', 'APPROVED');
INSERT INTO ads.assets (asset_id, customer_id, asset_type, text_content, global_approval) VALUES (1, 'test-cid', 'TEXT', 'Test headline', 'APPROVED');
INSERT INTO ads.asset_links (customer_id, link_level, asset_id, field_type, campaign_id, ad_group_id, ad_id, approval_status, link_status)
  VALUES ('test-cid', 'AD', 1, 'HEADLINE', 1, 1, 1, 'APPROVED', 'ENABLED');

-- Test 1: No alerts/incidents initially
SELECT is((SELECT count(*)::int FROM ads.policy_alerts), 0, 'No alerts initially');
SELECT is((SELECT count(*)::int FROM ads.policy_incidents), 0, 'No incidents initially');

-- Test 2: Disapproval → alert fires, incident opens
UPDATE ads.asset_links SET approval_status = 'DISAPPROVED' WHERE id = 1;

SELECT is((SELECT count(*)::int FROM ads.policy_alerts WHERE status = 'FIRING'), 1, 'One firing alert after disapproval');
SELECT is((SELECT count(*)::int FROM ads.policy_incidents WHERE status = 'OPEN'), 1, 'One open incident after disapproval');
SELECT is((SELECT firing_count FROM ads.policy_incidents WHERE status = 'OPEN'), 1, 'Incident firing_count should be 1');

-- Test 3: Re-approval → alert resolves, incident resolves
UPDATE ads.asset_links SET approval_status = 'APPROVED' WHERE id = 1;

SELECT is((SELECT count(*)::int FROM ads.policy_alerts WHERE status = 'FIRING'), 0, 'No firing alerts after re-approval');
SELECT is((SELECT status FROM ads.policy_incidents LIMIT 1), 'RESOLVED', 'Incident should be resolved');
SELECT isnt((SELECT resolved_at FROM ads.policy_incidents LIMIT 1), NULL, 'Incident resolved_at should be set');

SELECT * FROM finish();
ROLLBACK;
```

- [ ] **Step 2: Write the trigger function**

```sql
-- supabase/migrations/00016_create_incident_trigger.sql

CREATE OR REPLACE FUNCTION ads.manage_alerts_and_incidents()
RETURNS trigger AS $$
DECLARE
  v_incident_id uuid;
  v_asset_id bigint;
BEGIN
  -- Only care about approval_status changes on ASSET_LINK and AD entities
  IF NEW.field_name != 'approval_status' THEN
    RETURN NEW;
  END IF;

  IF NEW.entity_type NOT IN ('ASSET_LINK', 'AD') THEN
    RETURN NEW;
  END IF;

  -- Get the asset_id for this entity
  IF NEW.entity_type = 'ASSET_LINK' THEN
    SELECT asset_id INTO v_asset_id FROM ads.asset_links WHERE id = NEW.entity_id;
  ELSIF NEW.entity_type = 'AD' THEN
    -- For ads, we don't have a single asset_id. Skip ad-level incidents for now.
    -- Ad-level changes are tracked in status_changes only.
    RETURN NEW;
  END IF;

  IF v_asset_id IS NULL THEN
    RETURN NEW;
  END IF;

  -- ── ENTITY WENT NON-APPROVED → FIRE ALERT ──────────────────
  IF NEW.new_value IS NOT NULL AND NEW.new_value != 'APPROVED' AND
     (NEW.old_value IS NULL OR NEW.old_value = 'APPROVED') THEN

    -- Find or create incident for this asset
    SELECT id INTO v_incident_id
    FROM ads.policy_incidents
    WHERE customer_id = NEW.customer_id
      AND asset_id = v_asset_id
      AND status = 'OPEN';

    IF v_incident_id IS NULL THEN
      -- Check for a resolved incident to reopen
      SELECT id INTO v_incident_id
      FROM ads.policy_incidents
      WHERE customer_id = NEW.customer_id
        AND asset_id = v_asset_id
        AND status = 'RESOLVED'
      ORDER BY resolved_at DESC
      LIMIT 1;

      IF v_incident_id IS NOT NULL THEN
        -- Reopen
        UPDATE ads.policy_incidents
        SET status = 'OPEN', resolved_at = NULL, firing_count = 1, alert_count = alert_count + 1
        WHERE id = v_incident_id;
      ELSE
        -- Create new
        INSERT INTO ads.policy_incidents (customer_id, asset_id, alert_count, firing_count)
        VALUES (NEW.customer_id, v_asset_id, 1, 1)
        RETURNING id INTO v_incident_id;
      END IF;
    ELSE
      -- Existing open incident — increment counts
      UPDATE ads.policy_incidents
      SET firing_count = firing_count + 1, alert_count = alert_count + 1
      WHERE id = v_incident_id;
    END IF;

    -- Create the alert
    INSERT INTO ads.policy_alerts (
      customer_id, incident_id, entity_type, entity_id, asset_id,
      approval_status, previous_status
    ) VALUES (
      NEW.customer_id, v_incident_id, NEW.entity_type, NEW.entity_id, v_asset_id,
      NEW.new_value, NEW.old_value
    );
  END IF;

  -- ── ENTITY RETURNED TO APPROVED → RESOLVE ALERT ────────────
  IF NEW.new_value = 'APPROVED' AND NEW.old_value IS NOT NULL AND NEW.old_value != 'APPROVED' THEN

    -- Resolve the firing alert for this entity
    UPDATE ads.policy_alerts
    SET status = 'RESOLVED', resolved_at = now()
    WHERE entity_type = NEW.entity_type
      AND entity_id = NEW.entity_id
      AND status = 'FIRING';

    -- Decrement firing_count on the parent incident
    UPDATE ads.policy_incidents
    SET firing_count = firing_count - 1
    WHERE customer_id = NEW.customer_id
      AND asset_id = v_asset_id
      AND status = 'OPEN';

    -- If firing_count hits 0, resolve the incident
    UPDATE ads.policy_incidents
    SET status = 'RESOLVED', resolved_at = now()
    WHERE customer_id = NEW.customer_id
      AND asset_id = v_asset_id
      AND status = 'OPEN'
      AND firing_count <= 0;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_manage_incidents
  AFTER INSERT ON ads.status_changes
  FOR EACH ROW EXECUTE FUNCTION ads.manage_alerts_and_incidents();
```

- [ ] **Step 3: Apply and run tests**

```bash
supabase db reset && supabase test db
```

Expected: All 8 lifecycle tests pass.

- [ ] **Step 4: Commit**

```bash
git add supabase/migrations/ supabase/tests/
git commit -m "feat: add PagerDuty-style alert/incident management trigger"
```

---

### Task 3: Create flap detection

**Files:**
- Create: `supabase/migrations/00017_create_flap_detection.sql`
- Create: `supabase/tests/00012_flap_detection.sql`

- [ ] **Step 1: Write the test**

```sql
-- supabase/tests/00012_flap_detection.sql
BEGIN;
SELECT plan(3);

-- Seed
INSERT INTO ads.accounts (customer_id) VALUES ('test-cid');
INSERT INTO ads.campaigns (campaign_id, customer_id, name, status, serving_status) VALUES (1, 'test-cid', 'C1', 'ENABLED', 'SERVING');
INSERT INTO ads.ad_groups (ad_group_id, customer_id, campaign_id, name, status) VALUES (1, 'test-cid', 1, 'AG1', 'ENABLED');
INSERT INTO ads.ads (ad_id, customer_id, ad_group_id, status, approval_status) VALUES (1, 'test-cid', 1, 'ENABLED', 'APPROVED');
INSERT INTO ads.assets (asset_id, customer_id, asset_type, text_content, global_approval) VALUES (1, 'test-cid', 'TEXT', 'Flappy headline', 'APPROVED');
INSERT INTO ads.asset_links (customer_id, link_level, asset_id, field_type, campaign_id, ad_group_id, ad_id, approval_status, link_status)
  VALUES ('test-cid', 'AD', 1, 'HEADLINE', 1, 1, 1, 'APPROVED', 'ENABLED');

-- Flap 4 times (exceeds threshold of 3)
UPDATE ads.asset_links SET approval_status = 'DISAPPROVED' WHERE id = 1;
UPDATE ads.asset_links SET approval_status = 'APPROVED' WHERE id = 1;
UPDATE ads.asset_links SET approval_status = 'DISAPPROVED' WHERE id = 1;
UPDATE ads.asset_links SET approval_status = 'APPROVED' WHERE id = 1;

-- Test 1: Entity should be marked as flapping
SELECT is(
  (SELECT is_flapping FROM ads.flap_state WHERE entity_type = 'ASSET_LINK' AND entity_id = 1),
  true,
  'Entity should be flapping after 4 transitions'
);

-- Test 2: Status changes should still be logged (audit trail complete)
SELECT is(
  (SELECT count(*)::int FROM ads.status_changes WHERE entity_type = 'ASSET_LINK' AND entity_id = 1),
  4,
  'All 4 status changes should be logged even when flapping'
);

-- Test 3: Only 1 incident should exist (flapping suppresses after threshold)
-- First transition opens an incident, but subsequent ones after flap threshold do NOT
SELECT ok(
  (SELECT count(*)::int FROM ads.policy_incidents) <= 2,
  'Flapping should suppress new incidents after threshold'
);

SELECT * FROM finish();
ROLLBACK;
```

- [ ] **Step 2: Write the migration**

```sql
-- supabase/migrations/00017_create_flap_detection.sql

CREATE TABLE ads.flap_state (
  entity_type     text NOT NULL,
  entity_id       bigint NOT NULL,
  field_name      text NOT NULL,
  transition_count int NOT NULL DEFAULT 0,
  window_start    timestamptz NOT NULL DEFAULT now(),
  is_flapping     boolean NOT NULL DEFAULT false,
  PRIMARY KEY (entity_type, entity_id, field_name)
);

-- Modify the change detection triggers to update flap state
-- We add flap checking to the incident management trigger

CREATE OR REPLACE FUNCTION ads.update_flap_state()
RETURNS trigger AS $$
DECLARE
  v_is_flapping boolean;
BEGIN
  -- Upsert flap state
  INSERT INTO ads.flap_state (entity_type, entity_id, field_name, transition_count, window_start)
  VALUES (NEW.entity_type, NEW.entity_id, NEW.field_name, 1, now())
  ON CONFLICT (entity_type, entity_id, field_name)
  DO UPDATE SET
    transition_count = CASE
      -- Reset window if older than 24 hours
      WHEN ads.flap_state.window_start < now() - interval '24 hours'
        THEN 1
      ELSE ads.flap_state.transition_count + 1
    END,
    window_start = CASE
      WHEN ads.flap_state.window_start < now() - interval '24 hours'
        THEN now()
      ELSE ads.flap_state.window_start
    END,
    is_flapping = CASE
      WHEN ads.flap_state.window_start < now() - interval '24 hours'
        THEN false
      WHEN ads.flap_state.transition_count + 1 > 3
        THEN true
      ELSE ads.flap_state.is_flapping
    END;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Fire flap detection BEFORE incident management (so incidents can check flap state)
CREATE TRIGGER trg_flap_detection
  AFTER INSERT ON ads.status_changes
  FOR EACH ROW EXECUTE FUNCTION ads.update_flap_state();

-- Update incident trigger to check flap state
CREATE OR REPLACE FUNCTION ads.manage_alerts_and_incidents()
RETURNS trigger AS $$
DECLARE
  v_incident_id uuid;
  v_asset_id bigint;
  v_is_flapping boolean;
BEGIN
  IF NEW.field_name != 'approval_status' THEN RETURN NEW; END IF;
  IF NEW.entity_type NOT IN ('ASSET_LINK', 'AD') THEN RETURN NEW; END IF;

  -- Check flap state
  SELECT is_flapping INTO v_is_flapping
  FROM ads.flap_state
  WHERE entity_type = NEW.entity_type AND entity_id = NEW.entity_id AND field_name = NEW.field_name;

  IF NEW.entity_type = 'ASSET_LINK' THEN
    SELECT asset_id INTO v_asset_id FROM ads.asset_links WHERE id = NEW.entity_id;
  ELSE
    RETURN NEW;
  END IF;

  IF v_asset_id IS NULL THEN RETURN NEW; END IF;

  -- ENTITY WENT NON-APPROVED (and not flapping)
  IF NEW.new_value IS NOT NULL AND NEW.new_value != 'APPROVED'
     AND (NEW.old_value IS NULL OR NEW.old_value = 'APPROVED')
     AND (v_is_flapping IS NULL OR v_is_flapping = false) THEN

    SELECT id INTO v_incident_id FROM ads.policy_incidents
    WHERE customer_id = NEW.customer_id AND asset_id = v_asset_id AND status = 'OPEN';

    IF v_incident_id IS NULL THEN
      SELECT id INTO v_incident_id FROM ads.policy_incidents
      WHERE customer_id = NEW.customer_id AND asset_id = v_asset_id AND status = 'RESOLVED'
      ORDER BY resolved_at DESC LIMIT 1;

      IF v_incident_id IS NOT NULL THEN
        UPDATE ads.policy_incidents SET status = 'OPEN', resolved_at = NULL, firing_count = 1, alert_count = alert_count + 1 WHERE id = v_incident_id;
      ELSE
        INSERT INTO ads.policy_incidents (customer_id, asset_id, alert_count, firing_count)
        VALUES (NEW.customer_id, v_asset_id, 1, 1) RETURNING id INTO v_incident_id;
      END IF;
    ELSE
      UPDATE ads.policy_incidents SET firing_count = firing_count + 1, alert_count = alert_count + 1 WHERE id = v_incident_id;
    END IF;

    INSERT INTO ads.policy_alerts (customer_id, incident_id, entity_type, entity_id, asset_id, approval_status, previous_status)
    VALUES (NEW.customer_id, v_incident_id, NEW.entity_type, NEW.entity_id, v_asset_id, NEW.new_value, NEW.old_value);
  END IF;

  -- ENTITY RETURNED TO APPROVED
  IF NEW.new_value = 'APPROVED' AND NEW.old_value IS NOT NULL AND NEW.old_value != 'APPROVED' THEN
    UPDATE ads.policy_alerts SET status = 'RESOLVED', resolved_at = now()
    WHERE entity_type = NEW.entity_type AND entity_id = NEW.entity_id AND status = 'FIRING';

    UPDATE ads.policy_incidents SET firing_count = firing_count - 1
    WHERE customer_id = NEW.customer_id AND asset_id = v_asset_id AND status = 'OPEN';

    UPDATE ads.policy_incidents SET status = 'RESOLVED', resolved_at = now()
    WHERE customer_id = NEW.customer_id AND asset_id = v_asset_id AND status = 'OPEN' AND firing_count <= 0;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Recreate the trigger (DROP + CREATE to replace)
DROP TRIGGER IF EXISTS trg_manage_incidents ON ads.status_changes;
CREATE TRIGGER trg_manage_incidents
  AFTER INSERT ON ads.status_changes
  FOR EACH ROW EXECUTE FUNCTION ads.manage_alerts_and_incidents();
```

- [ ] **Step 3: Apply and run tests**

```bash
supabase db reset && supabase test db
```

- [ ] **Step 4: Commit**

```bash
git add supabase/migrations/ supabase/tests/
git commit -m "feat: add flap detection with suppression of alerts during flapping"
```

---

### Task 4: Create pipeline health monitoring view

**Files:**
- Create: `supabase/migrations/00018_create_pipeline_health.sql`

- [ ] **Step 1: Write the migration**

```sql
-- supabase/migrations/00018_create_pipeline_health.sql

CREATE OR REPLACE VIEW ads.pipeline_health AS
SELECT
  a.customer_id,
  a.descriptive_name,
  sr.last_sync,
  sr.last_sync_status,
  sr.last_sync_duration,
  sr.truncation_warnings,
  CASE
    WHEN sr.last_sync IS NULL THEN 'NEVER_SYNCED'
    WHEN sr.last_sync < now() - interval '2 hours' THEN 'MISSING'
    WHEN sr.last_sync_status = 'running' AND sr.last_sync < now() - interval '45 minutes' THEN 'STUCK'
    WHEN sr.last_sync_status = 'failed' THEN 'FAILED'
    WHEN sr.truncation_warnings IS NOT NULL AND array_length(sr.truncation_warnings, 1) > 0 THEN 'TRUNCATED'
    ELSE 'HEALTHY'
  END AS health_status
FROM ads.accounts a
LEFT JOIN LATERAL (
  SELECT
    completed_at AS last_sync,
    status AS last_sync_status,
    completed_at - started_at AS last_sync_duration,
    truncation_warnings
  FROM ads.sync_runs
  WHERE customer_id = a.customer_id
  ORDER BY started_at DESC
  LIMIT 1
) sr ON true;
```

- [ ] **Step 2: Apply**

```bash
supabase db reset && supabase test db
```

- [ ] **Step 3: Commit**

```bash
git add supabase/migrations/
git commit -m "feat: add pipeline_health monitoring view"
```

---

### Task 5: Enable Supabase Realtime

**Files:**
- Create: `supabase/migrations/00019_enable_realtime.sql`

- [ ] **Step 1: Write the migration**

```sql
-- supabase/migrations/00019_enable_realtime.sql

-- Enable Realtime for incident and alert tables
ALTER PUBLICATION supabase_realtime ADD TABLE ads.policy_incidents;
ALTER PUBLICATION supabase_realtime ADD TABLE ads.policy_alerts;
```

- [ ] **Step 2: Apply**

```bash
supabase db reset && supabase test db
```

- [ ] **Step 3: Commit**

```bash
git add supabase/migrations/
git commit -m "feat: enable Supabase Realtime on policy_incidents and policy_alerts"
```

---

### Task 6: Add data retention cleanup via pg_cron

**Files:**
- Create: `supabase/migrations/00020_create_retention_jobs.sql`

- [ ] **Step 1: Write the migration**

```sql
-- supabase/migrations/00020_create_retention_jobs.sql

-- Enable pg_cron if not already
CREATE EXTENSION IF NOT EXISTS pg_cron;

-- Prune status_changes older than 90 days (runs daily at 3am UTC)
SELECT cron.schedule(
  'cleanup-status-changes',
  '0 3 * * *',
  $$DELETE FROM ads.status_changes WHERE changed_at < now() - interval '90 days'$$
);

-- Prune resolved alerts older than 90 days
SELECT cron.schedule(
  'cleanup-resolved-alerts',
  '0 3 * * *',
  $$DELETE FROM ads.policy_alerts WHERE status = 'RESOLVED' AND resolved_at < now() - interval '90 days'$$
);

-- Prune sync_runs older than 30 days
SELECT cron.schedule(
  'cleanup-sync-runs',
  '0 3 * * *',
  $$DELETE FROM ads.sync_runs WHERE started_at < now() - interval '30 days'$$
);

-- Prune metrics older than 90 days
SELECT cron.schedule(
  'cleanup-metrics',
  '0 3 * * *',
  $$DELETE FROM ads.metrics_daily WHERE date < now() - interval '90 days'$$
);

-- Cleanup pg_cron's own job_run_details (prevents unbounded growth)
SELECT cron.schedule(
  'cleanup-cron-history',
  '0 4 * * *',
  $$DELETE FROM cron.job_run_details WHERE end_time < now() - interval '7 days'$$
);
```

- [ ] **Step 2: Apply (production only — pg_cron may not work locally)**

```bash
supabase db push
```

- [ ] **Step 3: Commit**

```bash
git add supabase/migrations/
git commit -m "feat: add pg_cron retention jobs for status_changes, alerts, sync_runs, metrics"
```

---

### Task 7: Schedule the Google Ads Script

**Files:** None (Google Ads UI configuration)

- [ ] **Step 1: Open the Google Ads Script in the UI**

Go to Google Ads → Tools → Bulk actions → Scripts → your script

- [ ] **Step 2: Set the schedule**

Click "Schedule" → Set to "Hourly"

- [ ] **Step 3: Verify first scheduled run**

After the first scheduled run, check:

```sql
-- Pipeline health
SELECT * FROM ads.pipeline_health;

-- Recent syncs
SELECT id, customer_id, status, started_at, completed_at,
       completed_at - started_at AS duration
FROM ads.sync_runs ORDER BY started_at DESC LIMIT 5;

-- Open incidents
SELECT i.id, a.text_content, a.asset_type, i.firing_count, i.opened_at
FROM ads.policy_incidents i
JOIN ads.assets a ON i.asset_id = a.asset_id AND i.customer_id = a.customer_id
WHERE i.status = 'OPEN';

-- The cascade
SELECT * FROM ads.cascade_status ORDER BY impact_level;
```

---

## Phase 5 Definition of Done

- [ ] `policy_alerts` and `policy_incidents` tables exist
- [ ] Alerts fire when entities go non-approved, resolve when they return to approved
- [ ] Incidents group alerts by root cause asset, auto-close when last alert resolves
- [ ] Flap detection suppresses alerts after 3 transitions in 24h
- [ ] `pipeline_health` view shows correct status for all accounts
- [ ] Supabase Realtime enabled on incidents and alerts tables
- [ ] pg_cron retention jobs scheduled
- [ ] Google Ads Script scheduled hourly
- [ ] All pgTAP tests pass
- [ ] All changes committed
