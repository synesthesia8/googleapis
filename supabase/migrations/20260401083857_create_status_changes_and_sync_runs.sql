CREATE TABLE ads.status_changes (
  id            bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  customer_id   text NOT NULL,
  entity_type   text NOT NULL,
  entity_id     bigint NOT NULL,
  field_name    text NOT NULL,
  old_value     text,
  new_value     text,
  changed_at    timestamptz NOT NULL DEFAULT now(),

  CONSTRAINT valid_entity_type CHECK (entity_type IN ('ASSET_LINK', 'AD', 'AD_GROUP', 'CAMPAIGN'))
);

CREATE INDEX idx_changes_lookup
  ON ads.status_changes (customer_id, entity_type, changed_at DESC);
CREATE INDEX idx_changes_entity
  ON ads.status_changes (entity_id, changed_at DESC);

CREATE TABLE ads.sync_runs (
  id                    uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  customer_id           text NOT NULL,
  started_at            timestamptz NOT NULL DEFAULT now(),
  completed_at          timestamptz,
  status                text NOT NULL DEFAULT 'running',
  is_first_sync         boolean NOT NULL DEFAULT false,
  rows_by_type          jsonb,
  truncation_warnings   text[],
  error                 text,

  CONSTRAINT valid_sync_status CHECK (status IN ('running', 'completed', 'failed'))
);
